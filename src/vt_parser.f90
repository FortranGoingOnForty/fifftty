module vt_parser
    use, intrinsic :: iso_c_binding
    use terminal_grid
    use pty_manager
    implicit none
    private

    ! Debug flag for escape sequence logging
    logical, parameter :: DEBUG_SEQUENCES = .true.

    ! Parser states (VT100/ANSI state machine)
    integer, parameter, public :: STATE_GROUND = 0
    integer, parameter, public :: STATE_ESCAPE = 1
    integer, parameter, public :: STATE_CSI_ENTRY = 2
    integer, parameter, public :: STATE_CSI_PARAM = 3
    integer, parameter, public :: STATE_CSI_INTERMEDIATE = 4
    integer, parameter, public :: STATE_OSC_STRING = 5
    integer, parameter, public :: STATE_ESCAPE_INTERMEDIATE = 6
    integer, parameter, public :: STATE_DCS_STRING = 7

    ! Maximum parameters in a CSI sequence
    integer, parameter :: MAX_PARAMS = 16

    ! VT parser type
    type, public :: parser_t
        integer :: state = STATE_GROUND
        integer :: params(MAX_PARAMS) = 0
        integer :: num_params = 0
        character(len=2) :: intermediates = ""
        logical :: private_mode = .false.   ! For CSI sequences starting with '?'
        integer :: current_fg = COLOR_DEFAULT
        integer :: current_bg = COLOR_DEFAULT
        integer :: current_attrs = 0
        type(c_ptr) :: pty_ptr = c_null_ptr  ! Pointer to PTY for sending responses
        ! Saved cursor position for save/restore operations
        integer :: saved_cursor_row = 0
        integer :: saved_cursor_col = 0
    contains
        procedure :: reset => parser_reset
        procedure :: process_byte => parser_process_byte
        procedure :: process_buffer => parser_process_buffer
        procedure :: set_pty => parser_set_pty
    end type parser_t

contains

    ! Reset parser to initial state
    subroutine parser_reset(this)
        class(parser_t), intent(inout) :: this
        this%state = STATE_GROUND
        this%params = 0
        this%num_params = 0
        this%intermediates = ""
        this%private_mode = .false.
        this%current_fg = COLOR_DEFAULT
        this%current_bg = COLOR_DEFAULT
        this%current_attrs = 0
    end subroutine parser_reset

    ! Set PTY for sending responses
    subroutine parser_set_pty(this, pty)
        class(parser_t), intent(inout) :: this
        type(pty_t), target, intent(in) :: pty
        this%pty_ptr = c_loc(pty)
    end subroutine parser_set_pty

    ! Process a single byte through the state machine
    subroutine parser_process_byte(this, grid, byte)
        class(parser_t), intent(inout) :: this
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        select case (this%state)
        case (STATE_GROUND)
            call handle_ground(this, grid, byte)
        case (STATE_ESCAPE)
            call handle_escape(this, grid, byte)
        case (STATE_ESCAPE_INTERMEDIATE)
            call handle_escape_intermediate(this, grid, byte)
        case (STATE_CSI_ENTRY)
            call handle_csi_entry(this, grid, byte)
        case (STATE_CSI_PARAM)
            call handle_csi_param(this, grid, byte)
        case (STATE_CSI_INTERMEDIATE)
            call handle_csi_intermediate(this, grid, byte)
        case (STATE_OSC_STRING)
            call handle_osc_string(this, grid, byte)
        case (STATE_DCS_STRING)
            call handle_dcs_string(this, grid, byte)
        end select
    end subroutine parser_process_byte

    ! Process a buffer of bytes
    subroutine parser_process_buffer(this, grid, buffer, length)
        class(parser_t), intent(inout) :: this
        type(grid_t), intent(inout) :: grid
        character(len=*), intent(in) :: buffer
        integer, intent(in) :: length
        integer :: i, byte

        do i = 1, length
            byte = ichar(buffer(i:i))
            ! Ultra-verbose debugging: log EVERY byte
            if (DEBUG_SEQUENCES .and. byte == 27) then
                print '(A)', "DEBUG: === ESC sequence starting ==="
            else if (DEBUG_SEQUENCES .and. byte == ichar('n') .and. i > 1) then
                if (ichar(buffer(i-1:i-1)) == ichar('6')) then
                    print '(A)', "CRITICAL: Detected '6n' sequence - possible CSI 6 n!"
                end if
            end if
            call this%process_byte(grid, byte)
        end do
    end subroutine parser_process_buffer

    ! Handle GROUND state (normal text)
    subroutine handle_ground(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte == 27) then  ! ESC
            parser%state = STATE_ESCAPE
        else if (byte == 10) then  ! LF (newline)
            call handle_newline(grid)
        else if (byte == 13) then  ! CR (carriage return)
            grid%cursor_col = 1
        else if (byte == 8) then  ! BS (backspace)
            if (grid%cursor_col > 1) grid%cursor_col = grid%cursor_col - 1
        else if (byte == 9) then  ! HT (tab)
            grid%cursor_col = ((grid%cursor_col - 1) / 8 + 1) * 8 + 1
            if (grid%cursor_col > grid%cols) call handle_newline(grid)
        else if (byte >= 32 .and. byte <= 126) then  ! Printable ASCII
            call write_char(parser, grid, byte)
        else if (byte == 7) then  ! BEL (bell)
            if (DEBUG_SEQUENCES) print '(A)', "DEBUG: BEL (bell) received"
        else if (byte == 14) then  ! SO (shift out)
            if (DEBUG_SEQUENCES) print '(A)', "DEBUG: SO (shift out) - charset switching"
        else if (byte == 15) then  ! SI (shift in)
            if (DEBUG_SEQUENCES) print '(A)', "DEBUG: SI (shift in) - charset switching"
        else if (byte > 0 .and. byte < 32) then  ! Other control characters
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,Z2.2)', "DEBUG: Ignored control char: ", byte, " (0x", byte, ")"
            end if
        else if (byte > 126) then  ! Extended ASCII/UTF-8
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,Z2.2)', "DEBUG: Extended char: ", byte, " (0x", byte, ")"
            end if
            ! For now, just write it as-is (will show as '?' likely)
            call write_char(parser, grid, byte)
        end if
    end subroutine handle_ground

    ! Handle ESCAPE state
    subroutine handle_escape(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (DEBUG_SEQUENCES) then
            if (byte >= 32 .and. byte <= 126) then
                print '(A,A,A,I0,A)', "DEBUG: ESC ", char(byte), " (", byte, ")"
            else
                print '(A,I0,A,Z2.2)', "DEBUG: ESC + byte ", byte, " (0x", byte, ")"
            end if
        end if

        if (byte == 91) then  ! '[' - CSI sequence
            parser%state = STATE_CSI_ENTRY
            parser%params = 0
            parser%num_params = 0
            parser%intermediates = ""
            parser%private_mode = .false.
        else if (byte == 93) then  ! ']' - OSC sequence
            parser%state = STATE_OSC_STRING
        else if (byte == 80) then  ! 'P' - DCS (Device Control String)
            parser%state = STATE_DCS_STRING
        else if (byte == 92) then  ! '\' - String terminator (ST)
            ! ESC \ terminates OSC/DCS/APC/PM/SOS sequences
            ! Just consume it and return to ground
            parser%state = STATE_GROUND
        else if (byte == 61) then  ! '=' - DECPAM (application keypad mode)
            ! Phase 1: ignore keypad mode changes
            parser%state = STATE_GROUND
        else if (byte == 62) then  ! '>' - DECPNM (normal keypad mode)
            ! Phase 1: ignore keypad mode changes
            parser%state = STATE_GROUND
        else if (byte == 40 .or. byte == 41 .or. byte == 42 .or. byte == 43) then  ! '(', ')', '*', '+'
            ! Charset selection sequences ESC ( X, ESC ) X, etc.
            ! Phase 1: consume the next byte (the charset designator) and ignore
            parser%state = STATE_ESCAPE_INTERMEDIATE
        else
            ! Unknown escape sequence, return to ground
            if (byte >= 32 .and. byte <= 126) then
                print '(A,A,A,I0,A)', "DEBUG: Unhandled ESC ", char(byte), " (", byte, ")"
            else
                print '(A,I0,A,Z2.2)', "DEBUG: Unhandled ESC+byte: ", byte, " (0x", byte, ")"
            end if
            parser%state = STATE_GROUND
        end if
    end subroutine handle_escape

    ! Handle ESCAPE_INTERMEDIATE state (consume one byte after certain ESC sequences)
    subroutine handle_escape_intermediate(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        ! Just consume the byte and return to ground
        ! Phase 1: ignore charset designators and other intermediate bytes
        parser%state = STATE_GROUND
    end subroutine handle_escape_intermediate

    ! Handle OSC_STRING state (Operating System Command)
    ! OSC sequences: ESC ] ... BEL or ESC ] ... ESC \
    subroutine handle_osc_string(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        ! Check for terminator
        if (byte == 7) then  ! BEL - terminate OSC
            parser%state = STATE_GROUND
        else if (byte == 27) then  ! ESC - might be ESC \ terminator
            ! For simplicity, treat ESC as terminator and return to ESCAPE state
            ! This handles ESC \ (next byte will be \) and other ESC sequences
            parser%state = STATE_ESCAPE
        end if
        ! All other bytes are consumed and ignored (Phase 1: no OSC handling)
    end subroutine handle_osc_string

    ! Handle DCS_STRING state (Device Control String)
    ! DCS sequences: ESC P ... BEL or ESC P ... ESC \
    subroutine handle_dcs_string(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        ! Check for terminator
        if (byte == 7) then  ! BEL - terminate DCS
            parser%state = STATE_GROUND
        else if (byte == 27) then  ! ESC - might be ESC \ terminator
            ! Return to ESCAPE state to handle the backslash
            parser%state = STATE_ESCAPE
        end if
        ! All other bytes are consumed and ignored (Phase 1: no DCS handling)
    end subroutine handle_dcs_string

    ! Handle CSI_ENTRY state
    subroutine handle_csi_entry(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte == 63) then  ! '?' - DEC private mode
            parser%private_mode = .true.
            parser%state = STATE_CSI_PARAM
            parser%num_params = 0
        else if (byte >= 48 .and. byte <= 57) then  ! '0'-'9'
            parser%state = STATE_CSI_PARAM
            parser%num_params = 1
            parser%params(1) = byte - 48
        else if (byte >= 64 .and. byte <= 126) then  ! Final byte
            call execute_csi(parser, grid, char(byte))
            parser%state = STATE_GROUND
            parser%private_mode = .false.
        else
            parser%state = STATE_GROUND
            parser%private_mode = .false.
        end if
    end subroutine handle_csi_entry

    ! Handle CSI_PARAM state
    subroutine handle_csi_param(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte >= 48 .and. byte <= 57) then  ! '0'-'9'
            ! If first digit after '?', initialize first param
            if (parser%num_params == 0) then
                parser%num_params = 1
                parser%params(1) = 0
            end if
            parser%params(parser%num_params) = parser%params(parser%num_params) * 10 + (byte - 48)
        else if (byte == 59) then  ! ';' - parameter separator
            if (parser%num_params < MAX_PARAMS) then
                parser%num_params = parser%num_params + 1
                parser%params(parser%num_params) = 0
            end if
        else if (byte >= 64 .and. byte <= 126) then  ! Final byte
            call execute_csi(parser, grid, char(byte))
            parser%state = STATE_GROUND
            parser%private_mode = .false.
        else
            parser%state = STATE_GROUND
            parser%private_mode = .false.
        end if
    end subroutine handle_csi_param

    ! Handle CSI_INTERMEDIATE state (for future use)
    subroutine handle_csi_intermediate(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte >= 64 .and. byte <= 126) then  ! Final byte
            call execute_csi(parser, grid, char(byte))
            parser%state = STATE_GROUND
        else
            parser%state = STATE_GROUND
        end if
    end subroutine handle_csi_intermediate

    ! Execute CSI sequence
    subroutine execute_csi(parser, grid, final_byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        character(len=1), intent(in) :: final_byte

        integer :: n, row, col
        character(len=32) :: response
        character(len=128) :: param_str
        integer :: i

        ! Build parameter string for debug output
        if (DEBUG_SEQUENCES .and. parser%num_params > 0) then
            write(param_str, '(20(I0,:,";"))') parser%params(1:min(parser%num_params, 20))
        else
            param_str = ""
        end if

        ! Phase 1: Ignore DEC private mode sequences (ESC[?...)
        if (parser%private_mode) then
            if (DEBUG_SEQUENCES) then
                print '(A,A,A,A,A)', "DEBUG: CSI ? ", trim(param_str), " ", final_byte, " (DEC private mode)"
            end if
            return
        end if

        if (DEBUG_SEQUENCES) then
            print '(A,A,A,A)', "DEBUG: CSI ", trim(param_str), " ", final_byte
        end if

        select case (final_byte)
        case ('A')  ! CUU - Cursor Up
            n = max(1, parser%params(1))
            grid%cursor_row = max(1, grid%cursor_row - n)

        case ('B')  ! CUD - Cursor Down
            n = max(1, parser%params(1))
            grid%cursor_row = min(grid%rows, grid%cursor_row + n)

        case ('C')  ! CUF - Cursor Forward
            n = max(1, parser%params(1))
            grid%cursor_col = min(grid%cols, grid%cursor_col + n)

        case ('D')  ! CUB - Cursor Back
            n = max(1, parser%params(1))
            grid%cursor_col = max(1, grid%cursor_col - n)

        case ('H', 'f')  ! CUP - Cursor Position
            row = max(1, parser%params(1))
            col = 1
            if (parser%num_params >= 2) col = max(1, parser%params(2))
            call grid%move_cursor(row, col)

        case ('J')  ! ED - Erase Display
            n = 0
            if (parser%num_params >= 1) n = parser%params(1)
            call erase_display(grid, n)

        case ('K')  ! EL - Erase Line
            n = 0
            if (parser%num_params >= 1) n = parser%params(1)
            call erase_line(grid, n)

        case ('m')  ! SGR - Select Graphic Rendition
            call handle_sgr(parser, grid)

        case ('c')  ! DA - Device Attributes
            ! Send VT100 response: ESC [ ? 1 ; 2 c
            if (DEBUG_SEQUENCES) then
                print '(A)', "IMPORTANT: Received CSI c (Device Attributes), sending ESC[?1;2c"
            end if
            call send_response(parser, char(27) // "[?1;2c")

        case ('n')  ! DSR - Device Status Report
            if (parser%num_params >= 1 .and. parser%params(1) == 6) then
                ! CPR - Cursor Position Report: ESC [ row ; col R
                write(response, '(A,I0,A,I0,A)') char(27) // "[", &
                      grid%cursor_row, ";", grid%cursor_col, "R"
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,I0)', "IMPORTANT: Received CSI 6 n, sending cursor position: ", &
                          grid%cursor_row, ",", grid%cursor_col
                end if
                call send_response(parser, trim(response))
            else if (DEBUG_SEQUENCES .and. parser%num_params >= 1) then
                print '(A,I0)', "DEBUG: CSI n with param: ", parser%params(1)
            end if


        case ('G')  ! CHA - Cursor Horizontal Absolute
            col = 1
            if (parser%num_params >= 1) col = max(1, parser%params(1))
            call grid%move_cursor(grid%cursor_row, col)

        case ('d')  ! VPA - Line Position Absolute
            row = 1
            if (parser%num_params >= 1) row = max(1, parser%params(1))
            call grid%move_cursor(row, grid%cursor_col)

        case ('P')  ! DCH - Delete Character
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            ! For now, just shift characters left
            ! TODO: Implement proper character deletion

        case ('@')  ! ICH - Insert Character
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            ! For now, just make space
            ! TODO: Implement proper character insertion

        case ('L')  ! IL - Insert Line
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            ! TODO: Implement line insertion

        case ('M')  ! DL - Delete Line
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            ! TODO: Implement line deletion

        case ('X')  ! ECH - Erase Character
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            ! Erase n characters from cursor position
            do i = 0, n-1
                if (grid%cursor_col + i <= grid%cols) then
                    grid%cells(grid%cursor_row, grid%cursor_col + i)%codepoint = 32  ! Space
                end if
            end do

        case ('s')  ! SCP - Save Cursor Position (non-standard but common)
            parser%saved_cursor_row = grid%cursor_row
            parser%saved_cursor_col = grid%cursor_col

        case ('u')  ! RCP - Restore Cursor Position (non-standard but common)
            if (parser%saved_cursor_row > 0 .and. parser%saved_cursor_col > 0) then
                call grid%move_cursor(parser%saved_cursor_row, parser%saved_cursor_col)
            end if

        case default
            if (DEBUG_SEQUENCES) then
                print '(A,A,A,20I0)', "DEBUG: Unhandled CSI ", final_byte, " params:", parser%params(1:min(parser%num_params, 20))
            end if
        end select
    end subroutine execute_csi

    ! Handle SGR (Select Graphic Rendition) - colors and attributes
    subroutine handle_sgr(parser, grid)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer :: i, param

        ! No params means reset
        if (parser%num_params == 0) then
            parser%current_fg = COLOR_DEFAULT
            parser%current_bg = COLOR_DEFAULT
            parser%current_attrs = 0
            return
        end if

        do i = 1, parser%num_params
            param = parser%params(i)

            if (param == 0) then
                ! Reset all attributes
                parser%current_fg = COLOR_DEFAULT
                parser%current_bg = COLOR_DEFAULT
                parser%current_attrs = 0
            else if (param == 1) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_BOLD)
            else if (param == 3) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_ITALIC)
            else if (param == 4) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_UNDERLINE)
            else if (param == 7) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_REVERSE)
            else if (param == 22) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_BOLD))
            else if (param == 23) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_ITALIC))
            else if (param == 24) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_UNDERLINE))
            else if (param == 27) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_REVERSE))
            else if (param >= 30 .and. param <= 37) then
                ! Foreground colors (30-37)
                parser%current_fg = param - 30
            else if (param >= 40 .and. param <= 47) then
                ! Background colors (40-47)
                parser%current_bg = param - 40
            else if (param >= 90 .and. param <= 97) then
                ! Bright foreground colors (90-97)
                parser%current_fg = param - 90 + 8
            else if (param >= 100 .and. param <= 107) then
                ! Bright background colors (100-107)
                parser%current_bg = param - 100 + 8
            end if
        end do
    end subroutine handle_sgr

    ! Erase display
    subroutine erase_display(grid, mode)
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: mode
        integer :: row, col

        select case (mode)
        case (0)  ! Clear from cursor to end of screen
            ! Clear from cursor to end of current line
            do col = grid%cursor_col, grid%cols
                call grid%set_cell(grid%cursor_row, col, 32, COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
            ! Clear all lines below
            do row = grid%cursor_row + 1, grid%rows
                call grid%clear_line(row)
            end do
        case (1)  ! Clear from beginning to cursor
            ! Clear all lines above current
            do row = 1, grid%cursor_row - 1
                call grid%clear_line(row)
            end do
            ! Clear from beginning of current line to cursor
            do col = 1, grid%cursor_col
                call grid%set_cell(grid%cursor_row, col, 32, COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        case (2, 3)  ! Clear entire screen
            call grid%clear()
        end select
    end subroutine erase_display

    ! Erase line
    subroutine erase_line(grid, mode)
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: mode
        integer :: col

        select case (mode)
        case (0)  ! Clear from cursor to end of line
            do col = grid%cursor_col, grid%cols
                call grid%set_cell(grid%cursor_row, col, 32, COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        case (1)  ! Clear from beginning to cursor
            do col = 1, grid%cursor_col
                call grid%set_cell(grid%cursor_row, col, 32, COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        case (2)  ! Clear entire line
            call grid%clear_line(grid%cursor_row)
        end select
    end subroutine erase_line

    ! Write a character to the grid
    subroutine write_char(parser, grid, codepoint)
        type(parser_t), intent(in) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: codepoint

        ! Write character at cursor position
        call grid%set_cell(grid%cursor_row, grid%cursor_col, codepoint, &
                          parser%current_fg, parser%current_bg, parser%current_attrs)

        ! Advance cursor
        grid%cursor_col = grid%cursor_col + 1

        ! Wrap to next line if needed
        if (grid%cursor_col > grid%cols) then
            call handle_newline(grid)
        end if
    end subroutine write_char

    ! Handle newline
    subroutine handle_newline(grid)
        type(grid_t), intent(inout) :: grid

        grid%cursor_row = grid%cursor_row + 1
        grid%cursor_col = 1

        ! Scroll if at bottom
        if (grid%cursor_row > grid%rows) then
            call grid%scroll_up()
            grid%cursor_row = grid%rows
        end if
    end subroutine handle_newline

    ! Send response to PTY
    subroutine send_response(parser, response)
        type(parser_t), intent(in) :: parser
        character(len=*), intent(in) :: response
        type(pty_t), pointer :: pty
        integer :: bytes_written
        integer :: i
        character(len=256) :: hex_str

        if (.not. c_associated(parser%pty_ptr)) then
            print '(A)', "ERROR: PTY not associated with parser!"
            return
        end if

        call c_f_pointer(parser%pty_ptr, pty)
        bytes_written = pty%write(response, len_trim(response))

        if (DEBUG_SEQUENCES) then
            ! Build hex string for debugging
            hex_str = ""
            do i = 1, min(len_trim(response), 20)
                write(hex_str(i*3-2:i*3), '(Z2.2,1X)') ichar(response(i:i))
            end do

            if (bytes_written < 0) then
                print '(A)', "ERROR: Failed to send response to PTY"
            else
                print '(A,I0,A,A)', "SENT TO PTY: ", bytes_written, " bytes: ", trim(hex_str)
            end if
        end if
    end subroutine send_response

end module vt_parser
