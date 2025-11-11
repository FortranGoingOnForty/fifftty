module vt_parser
    use terminal_grid
    implicit none
    private

    ! Parser states (VT100/ANSI state machine)
    integer, parameter, public :: STATE_GROUND = 0
    integer, parameter, public :: STATE_ESCAPE = 1
    integer, parameter, public :: STATE_CSI_ENTRY = 2
    integer, parameter, public :: STATE_CSI_PARAM = 3
    integer, parameter, public :: STATE_CSI_INTERMEDIATE = 4

    ! Maximum parameters in a CSI sequence
    integer, parameter :: MAX_PARAMS = 16

    ! VT parser type
    type, public :: parser_t
        integer :: state = STATE_GROUND
        integer :: params(MAX_PARAMS) = 0
        integer :: num_params = 0
        character(len=2) :: intermediates = ""
        integer :: current_fg = COLOR_DEFAULT
        integer :: current_bg = COLOR_DEFAULT
        integer :: current_attrs = 0
    contains
        procedure :: reset => parser_reset
        procedure :: process_byte => parser_process_byte
        procedure :: process_buffer => parser_process_buffer
    end type parser_t

contains

    ! Reset parser to initial state
    subroutine parser_reset(this)
        class(parser_t), intent(inout) :: this
        this%state = STATE_GROUND
        this%params = 0
        this%num_params = 0
        this%intermediates = ""
        this%current_fg = COLOR_DEFAULT
        this%current_bg = COLOR_DEFAULT
        this%current_attrs = 0
    end subroutine parser_reset

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
        case (STATE_CSI_ENTRY)
            call handle_csi_entry(this, grid, byte)
        case (STATE_CSI_PARAM)
            call handle_csi_param(this, grid, byte)
        case (STATE_CSI_INTERMEDIATE)
            call handle_csi_intermediate(this, grid, byte)
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
        end if
    end subroutine handle_ground

    ! Handle ESCAPE state
    subroutine handle_escape(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte == 91) then  ! '[' - CSI sequence
            parser%state = STATE_CSI_ENTRY
            parser%params = 0
            parser%num_params = 0
            parser%intermediates = ""
        else
            ! Unknown escape sequence, return to ground
            parser%state = STATE_GROUND
        end if
    end subroutine handle_escape

    ! Handle CSI_ENTRY state
    subroutine handle_csi_entry(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte >= 48 .and. byte <= 57) then  ! '0'-'9'
            parser%state = STATE_CSI_PARAM
            parser%num_params = 1
            parser%params(1) = byte - 48
        else if (byte >= 64 .and. byte <= 126) then  ! Final byte
            call execute_csi(parser, grid, char(byte))
            parser%state = STATE_GROUND
        else
            parser%state = STATE_GROUND
        end if
    end subroutine handle_csi_entry

    ! Handle CSI_PARAM state
    subroutine handle_csi_param(parser, grid, byte)
        type(parser_t), intent(inout) :: parser
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: byte

        if (byte >= 48 .and. byte <= 57) then  ! '0'-'9'
            parser%params(parser%num_params) = parser%params(parser%num_params) * 10 + (byte - 48)
        else if (byte == 59) then  ! ';' - parameter separator
            if (parser%num_params < MAX_PARAMS) then
                parser%num_params = parser%num_params + 1
                parser%params(parser%num_params) = 0
            end if
        else if (byte >= 64 .and. byte <= 126) then  ! Final byte
            call execute_csi(parser, grid, char(byte))
            parser%state = STATE_GROUND
        else
            parser%state = STATE_GROUND
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
        integer :: row

        select case (mode)
        case (0)  ! Clear from cursor to end of screen
            do row = grid%cursor_row, grid%rows
                call grid%clear_line(row)
            end do
        case (1)  ! Clear from beginning to cursor
            do row = 1, grid%cursor_row
                call grid%clear_line(row)
            end do
        case (2, 3)  ! Clear entire screen
            call grid%clear()
        end select
    end subroutine erase_display

    ! Erase line
    subroutine erase_line(grid, mode)
        type(grid_t), intent(inout) :: grid
        integer, intent(in) :: mode

        select case (mode)
        case (0, 1, 2)
            ! For Phase 1, just clear the entire line
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

end module vt_parser
