module vt_parser
    use, intrinsic :: iso_c_binding
    use terminal_grid
    use pty_manager
    implicit none
    private

    ! Debug flag for escape sequence logging
    logical, parameter :: DEBUG_SEQUENCES = .false.

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
        ! UTF-8 decoder state
        integer :: utf8_bytes_needed = 0    ! How many continuation bytes we're expecting
        integer :: utf8_codepoint = 0       ! Accumulator for the codepoint being built
        ! DEC private mode states
        logical :: application_cursor_keys = .false.  ! ?1 - DECCKM
        logical :: auto_wrap_mode = .true.            ! ?7 - DECAWM (enabled by default - most terminals)
        logical :: bracketed_paste_mode = .false.     ! ?2004
        ! Mouse tracking modes
        logical :: mouse_tracking_x10 = .false.       ! ?9 - X10 mouse
        logical :: mouse_tracking_vt200 = .false.     ! ?1000 - VT200 mouse
        logical :: mouse_tracking_btn = .false.       ! ?1002 - Button event tracking
        logical :: mouse_tracking_any = .false.       ! ?1003 - Any event tracking
        logical :: mouse_tracking_sgr = .false.       ! ?1006 - SGR extended mode
        ! OSC string buffer
        character(len=1024) :: osc_buffer = ""
        integer :: osc_buffer_len = 0
        ! Window title from OSC sequences
        character(len=256) :: window_title = "fortty"
        ! Hyperlink support (OSC 8)
        integer :: current_hyperlink_id = 0  ! Current hyperlink ID (0 = no link)
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
        this%utf8_bytes_needed = 0
        this%utf8_codepoint = 0
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

        ! DEBUG: Log ALL bytes to trace state machine
        if (DEBUG_SEQUENCES) then
            if (byte >= 32 .and. byte <= 126) then
                print '(A,I0,A,A,A,I0)', ">> BYTE: ", byte, " ('", char(byte), "') state=", this%state
            else
                print '(A,I0,A,Z2.2,A,I0)', ">> BYTE: ", byte, " (0x", byte, ") state=", this%state
            end if
        end if

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
        character(len=512) :: hex_dump
        integer :: hex_pos

        ! Build hex dump of entire buffer for debugging
        if (DEBUG_SEQUENCES .and. length > 0) then
            hex_dump = ""
            hex_pos = 1
            do i = 1, min(length, 50)  ! Limit to first 50 bytes for readability
                byte = ichar(buffer(i:i))
                write(hex_dump(hex_pos:hex_pos+3), '(Z2.2,A)') byte, " "
                hex_pos = hex_pos + 3

                ! Add readable char representation
                if (byte >= 32 .and. byte <= 126) then
                    hex_dump(hex_pos:hex_pos) = char(byte)
                else if (byte == 27) then
                    hex_dump(hex_pos:hex_pos) = "␛"  ! ESC symbol
                else if (byte == 10) then
                    hex_dump(hex_pos:hex_pos) = "␤"  ! LF symbol
                else if (byte == 13) then
                    hex_dump(hex_pos:hex_pos) = "␍"  ! CR symbol
                else
                    hex_dump(hex_pos:hex_pos) = "·"
                end if
                hex_pos = hex_pos + 2
            end do
            print '(A,I0,A)', "PTY_RECV[", length, " bytes]: " // trim(hex_dump)
        end if

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

        ! DEBUG: Log unexpected '0' or 'q' in GROUND state
        if (DEBUG_SEQUENCES .and. (byte == 48 .or. byte == 113)) then
            print '(A,I0,A,A,A)', "BUG: GROUND got byte ", byte, " ('", char(byte), "') - should be in CSI?"
        end if

        ! First, check if we're in the middle of a UTF-8 sequence
        if (parser%utf8_bytes_needed > 0) then
            ! We're expecting a UTF-8 continuation byte (10xxxxxx = 0x80-0xBF)
            if (byte >= 128 .and. byte <= 191) then  ! Valid continuation byte
                ! Extract the 6 data bits and add them to our codepoint
                parser%utf8_codepoint = ishft(parser%utf8_codepoint, 6) + iand(byte, 63)
                parser%utf8_bytes_needed = parser%utf8_bytes_needed - 1

                ! If we've received all bytes, write the complete character
                if (parser%utf8_bytes_needed == 0) then
                    if (DEBUG_SEQUENCES) then
                        print '(A,I0,A,Z0)', "DEBUG: UTF-8 complete, codepoint: ", &
                              parser%utf8_codepoint, " (0x", parser%utf8_codepoint, ")"
                    end if
                    call write_char(parser, grid, parser%utf8_codepoint)
                    parser%utf8_codepoint = 0
                end if
            else
                ! Invalid UTF-8 sequence - reset and treat this byte normally
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A)', "WARNING: Invalid UTF-8 continuation byte: ", byte, " - resetting"
                end if
                parser%utf8_bytes_needed = 0
                parser%utf8_codepoint = 0
                ! Fall through to handle this byte normally
            end if

            ! If we consumed a valid continuation byte, we're done
            if (parser%utf8_bytes_needed > 0 .or. (byte >= 128 .and. byte <= 191)) return
        end if

        ! Normal byte processing (not in UTF-8 sequence, or after resetting)
        if (byte == 27) then  ! ESC
            parser%state = STATE_ESCAPE
        else if (byte == 10) then  ! LF (newline)
            print '(A,I0,A,I0,A)', "LF: Newline from row=", grid%cursor_row, &
                " col=", grid%cursor_col, " (pending_wrap cleared)"
            call handle_newline(grid)
        else if (byte == 13) then  ! CR (carriage return)
            print '(A,I0,A,I0)', "CR: Move to col=1 (was col=", grid%cursor_col, &
                " row=", grid%cursor_row, ")"
            if (DEBUG_SEQUENCES .and. grid%pending_wrap) then
                print '(A)', "CR: Clearing pending_wrap"
            end if
            grid%cursor_col = 1
            grid%pending_wrap = .false.  ! Clear pending wrap on CR
        else if (byte == 8) then  ! BS (backspace)
            if (grid%cursor_col > 1) then
                grid%cursor_col = grid%cursor_col - 1
            else if (grid%cursor_row > 1) then
                ! Allow backspace to wrap to previous line (standard terminal behavior)
                grid%cursor_row = grid%cursor_row - 1
                grid%cursor_col = grid%cols
            end if
            grid%pending_wrap = .false.  ! Clear pending wrap on backspace
        else if (byte == 9) then  ! HT (tab)
            grid%cursor_col = ((grid%cursor_col - 1) / 8 + 1) * 8 + 1
            grid%pending_wrap = .false.  ! Clear pending wrap on tab
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
        else if (byte > 126) then  ! UTF-8 start bytes
            ! Determine how many bytes this UTF-8 character needs
            if (byte >= 192 .and. byte <= 223) then
                ! 2-byte sequence: 110xxxxx 10xxxxxx
                parser%utf8_bytes_needed = 1
                parser%utf8_codepoint = iand(byte, 31)  ! Extract 5 data bits
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,Z2.2)', "DEBUG: UTF-8 2-byte start: ", byte, " (0x", byte, ")"
                end if
            else if (byte >= 224 .and. byte <= 239) then
                ! 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
                parser%utf8_bytes_needed = 2
                parser%utf8_codepoint = iand(byte, 15)  ! Extract 4 data bits
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,Z2.2)', "DEBUG: UTF-8 3-byte start: ", byte, " (0x", byte, ")"
                end if
            else if (byte >= 240 .and. byte <= 247) then
                ! 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
                parser%utf8_bytes_needed = 3
                parser%utf8_codepoint = iand(byte, 7)   ! Extract 3 data bits
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,Z2.2)', "DEBUG: UTF-8 4-byte start: ", byte, " (0x", byte, ")"
                end if
            else
                ! Invalid UTF-8 start byte - write as '?'
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,Z2.2)', "WARNING: Invalid UTF-8 start byte: ", byte, " (0x", byte, ")"
                end if
                call write_char(parser, grid, 63)  ! '?'
            end if
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
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,I0,A)', "STATE CHANGE: ESCAPE → CSI_ENTRY (old=", parser%state, " new=", STATE_CSI_ENTRY, ")"
            end if
            parser%state = STATE_CSI_ENTRY
            parser%params = 0
            parser%num_params = 0
            parser%intermediates = ""
            parser%private_mode = .false.
        else if (byte == 93) then  ! ']' - OSC sequence
            if (DEBUG_SEQUENCES) then
                print '(A)', "DEBUG OSC: === ENTERING OSC STATE ==="
            end if
            parser%osc_buffer = ""
            parser%osc_buffer_len = 0
            parser%state = STATE_OSC_STRING
        else if (byte == 80) then  ! 'P' - DCS (Device Control String)
            if (DEBUG_SEQUENCES) then
                print '(A)', "DEBUG DCS: === ENTERING DCS STATE ==="
            end if
            parser%state = STATE_DCS_STRING
        else if (byte == 92) then  ! '\' - String terminator (ST)
            ! ESC \ terminates OSC/DCS/APC/PM/SOS sequences
            ! Just consume it and return to ground
            if (DEBUG_SEQUENCES) then
                print '(A)', "DEBUG OSC: Saw backslash (ST terminator), returning to GROUND"
            end if
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
        integer :: semicolon_pos, osc_num, ios
        character(len=:), allocatable :: osc_str

        ! Check for terminator
        if (byte == 7 .or. byte == 27) then  ! BEL or ESC
            ! Process the collected OSC string
            if (parser%osc_buffer_len > 0) then
                osc_str = parser%osc_buffer(1:parser%osc_buffer_len)

                ! Find semicolon separator
                semicolon_pos = index(osc_str, ';')

                if (semicolon_pos > 0) then
                    ! Parse OSC number
                    read(osc_str(1:semicolon_pos-1), *, iostat=ios) osc_num

                    ! Handle window title sequences (if read succeeded)
                    if (ios == 0 .and. (osc_num == 0 .or. osc_num == 2)) then
                        ! OSC 0 or 2 - Set window title
                        if (semicolon_pos < parser%osc_buffer_len) then
                            parser%window_title = osc_str(semicolon_pos+1:)
                            if (DEBUG_SEQUENCES) then
                                print '(A,A)', "OSC TITLE: ", trim(parser%window_title)
                            end if
                        end if
                    else if (ios == 0 .and. osc_num == 8) then
                        ! OSC 8 - Hyperlink: ESC ] 8 ; [params] ; [URL] ST
                        ! Find second semicolon (URL starts after it)
                        if (semicolon_pos < parser%osc_buffer_len) then
                            osc_str = osc_str(semicolon_pos+1:)  ! Skip "8;"
                            semicolon_pos = index(osc_str, ';')
                            if (semicolon_pos > 0) then
                                if (semicolon_pos < len(osc_str)) then
                                    ! URL present - assign hyperlink ID
                                    parser%current_hyperlink_id = 1  ! Simplified: just use 1 for any link
                                    if (DEBUG_SEQUENCES) then
                                        print '(A,A)', "OSC 8 HYPERLINK: ", trim(osc_str(semicolon_pos+1:))
                                    end if
                                else
                                    ! Empty URL - clear hyperlink
                                    parser%current_hyperlink_id = 0
                                end if
                            end if
                        end if
                    end if
                end if
            end if

            ! Return to appropriate state
            if (byte == 7) then
                parser%state = STATE_GROUND
            else
                parser%state = STATE_ESCAPE
            end if
        else
            ! Collect byte into buffer (if room)
            if (parser%osc_buffer_len < len(parser%osc_buffer)) then
                parser%osc_buffer_len = parser%osc_buffer_len + 1
                parser%osc_buffer(parser%osc_buffer_len:parser%osc_buffer_len) = char(byte)
            end if
        end if
    end subroutine handle_osc_string

    ! Handle DCS_STRING state (Device Control String)
    ! DCS sequences: ESC P ... BEL or ESC P ... ESC \
    subroutine handle_dcs_string(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        ! Check for terminator
        if (byte == 7) then  ! BEL - terminate DCS
            if (DEBUG_SEQUENCES) then
                print '(A)', "DEBUG DCS: Terminated by BEL, returning to GROUND"
            end if
            parser%state = STATE_GROUND
        else if (byte == 27) then  ! ESC - might be ESC \ terminator
            if (DEBUG_SEQUENCES) then
                print '(A)', "DEBUG DCS: Saw ESC, transitioning to ESCAPE state (expecting backslash)"
            end if
            ! Return to ESCAPE state to handle the backslash
            parser%state = STATE_ESCAPE
        else
            ! All other bytes are consumed and ignored (Phase 1: no DCS handling)
            if (DEBUG_SEQUENCES) then
                if (byte >= 32 .and. byte <= 126) then
                    print '(A,I0,A,A,A)', "DEBUG DCS: Consuming byte ", byte, " ('", char(byte), "')"
                else
                    print '(A,I0,A,Z2.2,A)', "DEBUG DCS: Consuming byte ", byte, " (0x", byte, ")"
                end if
            end if
        end if
    end subroutine handle_dcs_string

    ! Handle CSI_ENTRY state
    subroutine handle_csi_entry(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (DEBUG_SEQUENCES .and. byte == 91) then
            print '(A,I0)', "BUG: handle_csi_entry called with '[' (byte 91)! This should never happen!"
        end if

        if (byte == 63) then  ! '?' - DEC private mode
            parser%private_mode = .true.
            parser%state = STATE_CSI_PARAM
            parser%num_params = 0
        else if (byte >= 60 .and. byte <= 62) then  ! '<' '=' '>' - private/experimental markers
            ! Treat like '?' but don't set private_mode for now (Phase 1: ignore)
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
        integer :: i

        if (byte >= 48 .and. byte <= 57) then  ! '0'-'9'
            ! If first digit after '?', initialize first param
            if (parser%num_params == 0) then
                parser%num_params = 1
                parser%params(1) = 0
            end if
            if (DEBUG_SEQUENCES .and. parser%params(parser%num_params) > 1000) then
                print '(A,I0,A,I0,A,I0)', "WARNING: CSI param getting huge: ", &
                    parser%params(parser%num_params), " adding digit ", (byte-48), &
                    " num_params=", parser%num_params
            end if
            parser%params(parser%num_params) = parser%params(parser%num_params) * 10 + (byte - 48)
            if (DEBUG_SEQUENCES .and. byte == 48) then
                print '(A,I0)', "DEBUG: CSI_PARAM got '0', params=", parser%num_params
            end if
        else if (byte == 59) then  ! ';' - parameter separator
            if (parser%num_params < MAX_PARAMS) then
                parser%num_params = parser%num_params + 1
                parser%params(parser%num_params) = 0
            end if
        else if (byte >= 32 .and. byte <= 47) then  ! Intermediate bytes (0x20-0x2F)
            ! Store intermediate byte and transition to CSI_INTERMEDIATE state
            ! This handles sequences like CSI Ps SP q (DECSCUSR)
            if (len_trim(parser%intermediates) < len(parser%intermediates)) then
                parser%intermediates = trim(parser%intermediates) // char(byte)
            end if
            parser%state = STATE_CSI_INTERMEDIATE
        else if (byte >= 64 .and. byte <= 126) then  ! Final byte
            if (DEBUG_SEQUENCES .and. byte == 113) then
                print '(A,I0)', "DEBUG: CSI_PARAM got 'q' final, params=", parser%num_params
            end if
            ! Defensive: clamp parameters to prevent overflow (max reasonable value 10000)
            do i = 1, parser%num_params
                if (parser%params(i) > 10000) then
                    if (DEBUG_SEQUENCES) then
                        print '(A,I0,A)', "WARNING: Clamping huge CSI param ", parser%params(i), " to 10000"
                    end if
                    parser%params(i) = 10000
                end if
            end do
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

        ! Handle DEC private mode sequences (ESC[?...)
        if (parser%private_mode) then
            if (DEBUG_SEQUENCES) then
                print '(A,A,A,A,A)', "DEBUG: CSI ? ", trim(param_str), " ", final_byte, " (DEC private mode)"
            end if
            ! Handle key DEC private modes
            if (parser%num_params >= 1) then
                select case (parser%params(1))
                case (1)  ! DECCKM - Application cursor keys
                    if (final_byte == 'h') then
                        parser%application_cursor_keys = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "DECCKM: Application cursor keys enabled"
                    else if (final_byte == 'l') then
                        parser%application_cursor_keys = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "DECCKM: Normal cursor keys"
                    end if
                case (7)  ! DECAWM - Auto wrap mode
                    if (final_byte == 'h') then
                        parser%auto_wrap_mode = .true.
                        print '(A)', "DECAWM: Auto wrap ENABLED"
                    else if (final_byte == 'l') then
                        parser%auto_wrap_mode = .false.
                        print '(A)', "DECAWM: Auto wrap DISABLED"
                    end if
                case (25)  ! DECTCEM - Text cursor enable/disable
                    if (final_byte == 'h') then
                        grid%cursor_visible = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "DECTCEM: Cursor visible"
                    else if (final_byte == 'l') then
                        grid%cursor_visible = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "DECTCEM: Cursor hidden"
                    end if
                case (1049)  ! Alternate screen buffer with cursor save/restore
                    if (final_byte == 'h') then
                        call grid%switch_to_alt_screen()
                        if (DEBUG_SEQUENCES) print '(A)', "ALT_SCREEN: Switched to alternate screen"
                    else if (final_byte == 'l') then
                        call grid%switch_to_main_screen()
                        if (DEBUG_SEQUENCES) print '(A)', "ALT_SCREEN: Switched to main screen"
                    end if
                case (9)  ! X10 mouse reporting
                    if (final_byte == 'h') then
                        parser%mouse_tracking_x10 = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: X10 mode enabled"
                    else if (final_byte == 'l') then
                        parser%mouse_tracking_x10 = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: X10 mode disabled"
                    end if
                case (1000)  ! VT200 mouse reporting
                    if (final_byte == 'h') then
                        parser%mouse_tracking_vt200 = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: VT200 mode enabled"
                    else if (final_byte == 'l') then
                        parser%mouse_tracking_vt200 = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: VT200 mode disabled"
                    end if
                case (1002)  ! Button event tracking
                    if (final_byte == 'h') then
                        parser%mouse_tracking_btn = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: Button event tracking enabled"
                    else if (final_byte == 'l') then
                        parser%mouse_tracking_btn = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: Button event tracking disabled"
                    end if
                case (1003)  ! Any event tracking
                    if (final_byte == 'h') then
                        parser%mouse_tracking_any = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: Any event tracking enabled"
                    else if (final_byte == 'l') then
                        parser%mouse_tracking_any = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: Any event tracking disabled"
                    end if
                case (1006)  ! SGR extended mouse mode
                    if (final_byte == 'h') then
                        parser%mouse_tracking_sgr = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: SGR extended mode enabled"
                    else if (final_byte == 'l') then
                        parser%mouse_tracking_sgr = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "MOUSE: SGR extended mode disabled"
                    end if
                case (2004)  ! Bracketed paste mode
                    if (final_byte == 'h') then
                        parser%bracketed_paste_mode = .true.
                        if (DEBUG_SEQUENCES) print '(A)', "Bracketed paste mode enabled"
                    else if (final_byte == 'l') then
                        parser%bracketed_paste_mode = .false.
                        if (DEBUG_SEQUENCES) print '(A)', "Bracketed paste mode disabled"
                    end if
                end select
            end if
            return
        end if

        if (DEBUG_SEQUENCES) then
            print '(A,A,A,A)', "DEBUG: CSI ", trim(param_str), " ", final_byte
        end if

        select case (final_byte)
        case ('A')  ! CUU - Cursor Up (relative - preserve pending_wrap)
            n = max(1, parser%params(1))
            grid%cursor_row = max(1, grid%cursor_row - n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,I0)', "CURSOR UP by ", n, " -> row=", grid%cursor_row
            end if

        case ('B')  ! CUD - Cursor Down (relative - preserve pending_wrap)
            n = max(1, parser%params(1))
            grid%cursor_row = min(grid%rows, grid%cursor_row + n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,I0)', "CURSOR DOWN by ", n, " -> row=", grid%cursor_row
            end if

        case ('C')  ! CUF - Cursor Forward (relative - preserve pending_wrap)
            n = max(1, parser%params(1))
            col = grid%cursor_col
            grid%cursor_col = min(grid%cols, grid%cursor_col + n)
            print '(A,I0,A,I0,A,I0,A,I0)', "CUF: Forward ", n, " from col=", col, &
                " to col=", grid%cursor_col, " (grid_cols=", grid%cols, ")"

        case ('D')  ! CUB - Cursor Back
            n = max(1, parser%params(1))
            col = grid%cursor_col
            grid%cursor_col = max(1, grid%cursor_col - n)
            print '(A,I0,A,I0,A,I0,A,I0)', "CUB: Back ", n, " from col=", col, &
                " to col=", grid%cursor_col, " (grid_cols=", grid%cols, ")"
            ! CUB clears pending wrap since we're moving away from the edge
            if (grid%pending_wrap) then
                if (DEBUG_SEQUENCES) then
                    print '(A)', "CUB: Clearing pending_wrap"
                end if
                grid%pending_wrap = .false.
            end if

        case ('H', 'f')  ! CUP - Cursor Position (absolute - clear pending_wrap)
            row = max(1, parser%params(1))
            col = 1
            if (parser%num_params >= 2) col = max(1, parser%params(2))
            print '(A,I0,A,I0,A,I0,A,I0)', "CUP: Move to row=", row, " col=", col, &
                " (grid: ", grid%rows, "x", grid%cols, ")"
            call grid%move_cursor(row, col)
            if (DEBUG_SEQUENCES .and. grid%pending_wrap) then
                print '(A,I0,A,I0,A)', "CUP: Clearing pending_wrap (absolute positioning to ", row, ",", col, ")"
            end if
            grid%pending_wrap = .false.

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
            ! Send modern xterm-256color response: ESC [ ? 6 2 ; 9 ; 2 2 c
            ! Params: 62=VT220, 9=National replacement charset, 22=Color text
            ! This matches what modern xterm/alacritty/wezterm send
            ! Tells zsh we're a capable modern terminal with proper cursor control
            if (DEBUG_SEQUENCES) then
                print '(A)', "IMPORTANT: Received CSI c (Device Attributes), sending ESC[?62;9;22c (VT220+color)"
            end if
            call send_response(parser, char(27) // "[?62;9;22c")

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
            print '(A,I0,A,I0,A,I0)', "CHA: Move to col ", col, " (grid cols=", grid%cols, &
                ", requested=", parser%params(1), ")"
            call grid%move_cursor(grid%cursor_row, col)
            grid%pending_wrap = .false.  ! Clear pending wrap on absolute positioning

        case ('d')  ! VPA - Line Position Absolute
            row = 1
            if (parser%num_params >= 1) row = max(1, parser%params(1))
            call grid%move_cursor(row, grid%cursor_col)

        case ('r')  ! DECSTBM - Set Top and Bottom Margins (scrolling region)
            if (parser%num_params == 0) then
                ! No parameters - reset to full screen
                call grid%set_scroll_region(0, 0)
            else if (parser%num_params >= 2) then
                ! Set specific region
                call grid%set_scroll_region(parser%params(1), parser%params(2))
            end if
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,I0)', "SET SCROLL REGION: ", grid%scroll_top, " to ", grid%scroll_bottom
            end if

        case ('P')  ! DCH - Delete Character
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            call grid%delete_chars(n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0)', "DELETE CHARS: ", n
            end if

        case ('@')  ! ICH - Insert Character
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            call grid%insert_chars(n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0)', "INSERT CHARS: ", n
            end if

        case ('L')  ! IL - Insert Line
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            call grid%insert_lines(n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0)', "INSERT LINES: ", n
            end if

        case ('M')  ! DL - Delete Line
            n = 1
            if (parser%num_params >= 1) n = max(1, parser%params(1))
            call grid%delete_lines(n)
            if (DEBUG_SEQUENCES) then
                print '(A,I0)', "DELETE LINES: ", n
            end if

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

        case ('q')  ! DECSCUSR - Set Cursor Style
            ! CSI n q where n is: 0=blink block, 1=blink block, 2=steady block, 3=blink underline, etc.
            ! Phase 1: Just consume and ignore - we'll implement cursor styles in Phase 6
            if (DEBUG_SEQUENCES) then
                if (parser%num_params >= 1) then
                    print '(A,I0)', "DEBUG: CSI q (cursor style) param: ", parser%params(1)
                else
                    print '(A)', "DEBUG: CSI q (cursor style) no params"
                end if
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

        i = 1
        do while (i <= parser%num_params)
            param = parser%params(i)

            if (param == 0) then
                ! Reset all attributes
                parser%current_fg = COLOR_DEFAULT
                parser%current_bg = COLOR_DEFAULT
                parser%current_attrs = 0
                if (DEBUG_SEQUENCES) then
                    print '(A)', "DEBUG: SGR reset - all attributes cleared"
                end if
            else if (param == 1) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_BOLD)
            else if (param == 3) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_ITALIC)
            else if (param == 4) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_UNDERLINE)
                if (DEBUG_SEQUENCES) then
                    print '(A,Z8)', "DEBUG: Underline ON, attrs now = ", parser%current_attrs
                end if
            else if (param == 7) then
                parser%current_attrs = ior(parser%current_attrs, ATTR_REVERSE)
            else if (param == 22) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_BOLD))
            else if (param == 23) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_ITALIC))
            else if (param == 24) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_UNDERLINE))
                if (DEBUG_SEQUENCES) then
                    print '(A,Z8)', "DEBUG: Underline OFF, attrs now = ", parser%current_attrs
                end if
            else if (param == 27) then
                parser%current_attrs = iand(parser%current_attrs, not(ATTR_REVERSE))
            else if (param >= 30 .and. param <= 37) then
                ! Foreground colors (30-37)
                parser%current_fg = param - 30
            else if (param == 38) then
                ! Extended foreground color
                if (i + 1 <= parser%num_params) then
                    if (parser%params(i + 1) == 5 .and. i + 2 <= parser%num_params) then
                        ! 256-color: ESC[38;5;{n}m
                        parser%current_fg = parser%params(i + 2)
                        i = i + 2  ! Skip next two parameters
                    else if (parser%params(i + 1) == 2 .and. i + 4 <= parser%num_params) then
                        ! 24-bit color: ESC[38;2;{r};{g};{b}m
                        ! Pack RGB into negative integer: -(R*65536 + G*256 + B + 1)
                        parser%current_fg = -(parser%params(i + 2) * 65536 + &
                                               parser%params(i + 3) * 256 + &
                                               parser%params(i + 4) + 1)
                        i = i + 4  ! Skip next four parameters
                    end if
                end if
            else if (param == 39) then
                ! Reset foreground to default
                parser%current_fg = COLOR_DEFAULT
            else if (param >= 40 .and. param <= 47) then
                ! Background colors (40-47)
                parser%current_bg = param - 40
            else if (param == 48) then
                ! Extended background color
                if (i + 1 <= parser%num_params) then
                    if (parser%params(i + 1) == 5 .and. i + 2 <= parser%num_params) then
                        ! 256-color: ESC[48;5;{n}m
                        parser%current_bg = parser%params(i + 2)
                        i = i + 2  ! Skip next two parameters
                    else if (parser%params(i + 1) == 2 .and. i + 4 <= parser%num_params) then
                        ! 24-bit color: ESC[48;2;{r};{g};{b}m
                        ! Pack RGB into negative integer: -(R*65536 + G*256 + B + 1)
                        parser%current_bg = -(parser%params(i + 2) * 65536 + &
                                               parser%params(i + 3) * 256 + &
                                               parser%params(i + 4) + 1)
                        i = i + 4  ! Skip next four parameters
                    end if
                end if
            else if (param == 49) then
                ! Reset background to default
                parser%current_bg = COLOR_DEFAULT
            else if (param >= 90 .and. param <= 97) then
                ! Bright foreground colors (90-97)
                parser%current_fg = param - 90 + 8
            else if (param >= 100 .and. param <= 107) then
                ! Bright background colors (100-107)
                parser%current_bg = param - 100 + 8
            end if

            i = i + 1
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
            ! VT100 spec: ED 2 does NOT move cursor - cursor stays at current position
            ! Save cursor position, clear, then restore
            row = grid%cursor_row
            col = grid%cursor_col
            call grid%clear()
            grid%cursor_row = row
            grid%cursor_col = col
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

    ! Get the display width of a Unicode character (wcwidth equivalent)
    ! Returns: 0 for zero-width, 1 for normal, 2 for double-width
    function get_char_width(codepoint) result(width)
        integer, intent(in) :: codepoint
        integer :: width

        ! Zero-width characters
        if (codepoint == 0) then
            width = 0
            return
        end if

        ! Combining marks and other zero-width (U+0300-U+036F, U+1AB0-U+1AFF, etc.)
        if ((codepoint >= 768 .and. codepoint <= 879) .or. &     ! Combining Diacritical Marks
            (codepoint >= 6832 .and. codepoint <= 6911) .or. &   ! Combining Diacritical Marks Extended
            (codepoint >= 7616 .and. codepoint <= 7679) .or. &   ! Combining Diacritical Marks Supplement
            (codepoint >= 8400 .and. codepoint <= 8447)) then    ! Combining Marks for Symbols
            width = 0
            return
        end if

        ! Double-width characters (East Asian Wide and Fullwidth)
        ! CJK Unified Ideographs: U+4E00-U+9FFF
        if (codepoint >= 19968 .and. codepoint <= 40959) then
            width = 2
            return
        end if

        ! Hangul Syllables: U+AC00-U+D7AF
        if (codepoint >= 44032 .and. codepoint <= 55215) then
            width = 2
            return
        end if

        ! Fullwidth Latin: U+FF00-U+FF60
        if (codepoint >= 65280 .and. codepoint <= 65376) then
            width = 2
            return
        end if

        ! Emoji and symbols (common double-width ranges)
        ! Miscellaneous Symbols and Pictographs: U+1F300-U+1F5FF
        if (codepoint >= 127744 .and. codepoint <= 128511) then
            width = 2
            return
        end if

        ! Emoticons: U+1F600-U+1F64F
        if (codepoint >= 128512 .and. codepoint <= 128591) then
            width = 2
            return
        end if

        ! Transport and Map Symbols: U+1F680-U+1F6FF
        if (codepoint >= 128640 .and. codepoint <= 128767) then
            width = 2
            return
        end if

        ! Supplemental Symbols and Pictographs: U+1F900-U+1F9FF
        if (codepoint >= 129280 .and. codepoint <= 129535) then
            width = 2
            return
        end if

        ! Dingbats: U+2700-U+27BF (includes checkmarks, crosses, etc.)
        if (codepoint >= 9984 .and. codepoint <= 10175) then
            width = 2
            return
        end if

        ! Miscellaneous Symbols: U+2600-U+26FF
        if (codepoint >= 9728 .and. codepoint <= 9983) then
            width = 2
            return
        end if

        ! Default to single-width
        width = 1
    end function get_char_width

    ! Write a character to the grid
    subroutine write_char(parser, grid, codepoint)
        type(parser_t), intent(in) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: codepoint
        integer :: char_width
        integer :: prev_col
        type(cell_t) :: cell

        ! DEBUG disabled - verbose character logging
        ! if (grid%cursor_col >= grid%cols - 5) then
        !     if (codepoint >= 32 .and. codepoint <= 126) then
        !         print '(A,A,A,I0,A,I0,A,I0)', "NEAR_EDGE: '", char(codepoint), &
        !               "' row=", grid%cursor_row, " col=", grid%cursor_col, " grid_cols=", grid%cols
        !     end if
        ! end if

        ! VT100 pending wrap: if we're in pending wrap state AND still at last column, wrap now
        ! Only if auto-wrap mode is enabled
        ! If cursor was moved away from edge, clear pending_wrap without wrapping
        if (grid%pending_wrap) then
            if (grid%cursor_col == grid%cols) then
                if (parser%auto_wrap_mode) then
                    ! Still at edge and autowrap enabled - perform the wrap
                    if (DEBUG_SEQUENCES) then
                        print '(A,I0,A)', "PENDING_WRAP: Wrapping before writing char ", codepoint, " ('"//char(codepoint)//"')"
                    end if
                    call handle_newline(grid)
                else
                    ! Autowrap disabled - just overwrite the last character
                    if (DEBUG_SEQUENCES) then
                        print '(A)', "PENDING_WRAP: Auto-wrap disabled, will overwrite last char"
                    end if
                end if
            else
                ! Cursor moved away from edge - just clear the flag
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,I0)', "PENDING_WRAP: Clearing (cursor at col ", grid%cursor_col, ", not at edge)"
                end if
            end if
            grid%pending_wrap = .false.
        end if

        ! If cursor is past the edge, write at last column
        ! This shouldn't happen normally, but handle it gracefully
        if (grid%cursor_col > grid%cols) then
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A,I0,A)', "PAST_EDGE: cursor past edge (col=", grid%cursor_col, &
                    " > ", grid%cols, "), clamping to last column"
            end if
            grid%cursor_col = grid%cols
        end if

        ! Get the display width of this character
        char_width = get_char_width(codepoint)

        if (DEBUG_SEQUENCES .and. char_width > 1) then
            print '(A,I0,A,I0)', "DEBUG: Double-width char! Width=", char_width, &
                  " cursor_col before: ", grid%cursor_col
        end if

        ! If we're about to overwrite a wide char continuation cell (marked with codepoint 0),
        ! clear the preceding cell that contains the actual wide character
        if (grid%cursor_col > 1) then
            cell = grid%get_cell(grid%cursor_row, grid%cursor_col)
            if (cell%codepoint == 0) then
                ! This is a wide char continuation - clear the preceding cell
                call grid%set_cell(grid%cursor_row, grid%cursor_col - 1, 32, &
                                  parser%current_fg, parser%current_bg, 0)
            end if
        end if

        ! Write character at cursor position
        ! Debug: show ALL character writes to see RPROMPT positioning
        if (codepoint >= 32 .and. codepoint <= 126) then
            print '(A,A,A,I0,A,I0,A,I0,A)', "WRITE_CHAR: '", char(codepoint), "' at row=", &
                grid%cursor_row, " col=", grid%cursor_col, "/", grid%cols, &
                " pending_wrap=", merge("T", "F", grid%pending_wrap)
        end if
        call grid%set_cell(grid%cursor_row, grid%cursor_col, codepoint, &
                          parser%current_fg, parser%current_bg, parser%current_attrs, &
                          parser%current_hyperlink_id)

        ! For double-width characters, mark the next cell as a continuation (codepoint 0)
        if (char_width == 2 .and. grid%cursor_col < grid%cols) then
            call grid%set_cell(grid%cursor_row, grid%cursor_col + 1, 0, &
                              parser%current_fg, parser%current_bg, parser%current_attrs, &
                              parser%current_hyperlink_id)
            if (DEBUG_SEQUENCES) then
                print '(A,I0,A)', "DEBUG: Marked col ", grid%cursor_col + 1, " as wide char continuation"
            end if
        end if

        ! Advance cursor by character width (1 or 2 columns)
        ! BUT: don't advance if we're at the last column - just stay there
        ! This allows RPROMPT to work by overwriting at the last column
        prev_col = grid%cursor_col
        if (grid%cursor_col < grid%cols) then
            ! Not at edge yet - advance normally
            grid%cursor_col = grid%cursor_col + char_width
        else
            ! Already at last column - don't advance (overwrite mode)
            if (DEBUG_SEQUENCES) then
                print '(A)', "AT_EDGE: Not advancing cursor (already at last column)"
            end if
        end if

        if (DEBUG_SEQUENCES .and. char_width > 1) then
            print '(A,I0)', "DEBUG: cursor_col after: ", grid%cursor_col
        end if

        ! Handle cursor going past edge
        if (grid%cursor_col == grid%cols + 1) then
            ! Cursor went one past edge - clamp back
            grid%cursor_col = grid%cols
            ! Note: we don't set pending_wrap for modern terminal behavior
        else if (grid%cursor_col > grid%cols + 1) then
            ! For double-width chars that go past cols+1, wrap immediately (if autowrap enabled)
            if (parser%auto_wrap_mode) then
                if (DEBUG_SEQUENCES) then
                    print '(A,I0,A,I0,A,I0)', "EDGE: cursor past cols+1 (", grid%cursor_col, &
                        " > ", grid%cols + 1, "), wrapping immediately, char=", codepoint
                end if
                call handle_newline(grid)
            else
                ! Clamp to cols+1 if autowrap disabled
                grid%cursor_col = grid%cols + 1
                if (DEBUG_SEQUENCES) then
                    print '(A)', "EDGE: double-width char past edge, autowrap disabled - clamping to cols+1"
                end if
            end if
        end if
    end subroutine write_char

    ! Handle newline
    subroutine handle_newline(grid)
        type(grid_t), intent(inout) :: grid
        logical, parameter :: DEBUG_NEWLINES = .false.

        if (DEBUG_NEWLINES) then
            print '(A,I0,A,I0)', "NEWLINE: row ", grid%cursor_row, " -> ", grid%cursor_row + 1
        end if

        grid%cursor_row = grid%cursor_row + 1
        grid%cursor_col = 1
        grid%pending_wrap = .false.  ! Clear pending wrap on newline

        ! Scroll if at bottom
        if (grid%cursor_row > grid%rows) then
            call grid%scroll_up()
            grid%cursor_row = grid%rows
            if (DEBUG_NEWLINES) then
                print '(A,I0)', "NEWLINE: scrolled, clamped to row=", grid%rows
            end if
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
