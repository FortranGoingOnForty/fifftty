! Unit tests for VT100/ANSI escape sequence parser
program test_vt_parser
    use test_framework
    use vt_parser
    use terminal_grid
    implicit none

    type(parser_t) :: parser
    type(grid_t) :: grid
    integer :: exit_code

    call reset_test_stats()

    ! Initialize test grid (24 rows x 80 cols)
    call grid%init(24, 80)

    ! Run test suites
    call test_basic_text()
    call test_control_characters()
    call test_cursor_movement()
    call test_erase_display()
    call test_erase_line()
    call test_sgr_colors()
    call test_sgr_attributes()
    call test_state_machine()

    ! Print summary and get exit code
    exit_code = test_summary()

    ! Exit with error code if any tests failed
    if (exit_code /= 0) then
        stop 1
    end if

contains

    ! Helper function to get codepoint at a position
    function get_cp(row, col) result(cp)
        integer, intent(in) :: row, col
        integer :: cp
        type(cell_t) :: cell
        cell = grid%get_cell(row, col)
        cp = cell%codepoint
    end function get_cp

    ! ========================================
    ! Test basic text rendering
    ! ========================================
    subroutine test_basic_text()
        call test_begin("Basic text - single character")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, "A", 1)
        call assert_equal_int(get_cp(1, 1), ichar('A'), "Character should be 'A'")
        call assert_equal_int(grid%cursor_row, 1, "Cursor should be on row 1")
        call assert_equal_int(grid%cursor_col, 2, "Cursor should be on col 2")
        call test_end()

        call test_begin("Basic text - multiple characters")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, "Hello", 5)
        call assert_equal_int(get_cp(1, 1), ichar('H'), "First char should be 'H'")
        call assert_equal_int(get_cp(1, 2), ichar('e'), "Second char should be 'e'")
        call assert_equal_int(get_cp(1, 5), ichar('o'), "Fifth char should be 'o'")
        call assert_equal_int(grid%cursor_col, 6, "Cursor should be at col 6")
        call test_end()

        call test_begin("Basic text - line wrapping")
        call grid%clear()
        call parser%reset()

        ! Write exactly 80 characters (should wrap to next line)
        call parser%process_buffer(grid, repeat("X", 80), 80)
        call assert_equal_int(grid%cursor_row, 2, "Cursor should wrap to row 2")
        call assert_equal_int(grid%cursor_col, 1, "Cursor should be at col 1 after wrap")
        call test_end()
    end subroutine test_basic_text

    ! ========================================
    ! Test control characters
    ! ========================================
    subroutine test_control_characters()
        character(len=10) :: buffer

        call test_begin("Control - linefeed (LF)")
        call grid%clear()
        call parser%reset()

        buffer(1:1) = char(10)  ! LF
        call parser%process_buffer(grid, buffer(1:1), 1)
        call assert_equal_int(grid%cursor_row, 2, "LF should move to next row")
        call assert_equal_int(grid%cursor_col, 1, "LF should move to col 1")
        call test_end()

        call test_begin("Control - carriage return (CR)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, "Hello", 5)
        buffer(1:1) = char(13)  ! CR
        call parser%process_buffer(grid, buffer(1:1), 1)
        call assert_equal_int(grid%cursor_row, 1, "CR should keep same row")
        call assert_equal_int(grid%cursor_col, 1, "CR should move to col 1")
        call test_end()

        call test_begin("Control - backspace (BS)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, "AB", 2)
        buffer(1:1) = char(8)  ! BS
        call parser%process_buffer(grid, buffer(1:1), 1)
        call assert_equal_int(grid%cursor_col, 2, "BS should move cursor back")
        call test_end()

        call test_begin("Control - tab (HT)")
        call grid%clear()
        call parser%reset()

        buffer(1:1) = char(9)  ! HT
        call parser%process_buffer(grid, buffer(1:1), 1)
        call assert_equal_int(grid%cursor_col, 9, "Tab from col 1 should move to col 9")
        call test_end()

        call test_begin("Control - CRLF sequence")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, "Line1", 5)
        buffer(1:2) = char(13) // char(10)  ! CR LF
        call parser%process_buffer(grid, buffer(1:2), 2)
        call parser%process_buffer(grid, "Line2", 5)
        call assert_equal_int(get_cp(1, 1), ichar('L'), "First line should start with 'L'")
        call assert_equal_int(get_cp(2, 1), ichar('L'), "Second line should start with 'L'")
        call test_end()
    end subroutine test_control_characters

    ! ========================================
    ! Test cursor movement CSI sequences
    ! ========================================
    subroutine test_cursor_movement()
        call test_begin("Cursor - CUU (Cursor Up)")
        call grid%clear()
        call parser%reset()
        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 2 A - move up 2 rows
        call parser%process_buffer(grid, char(27) // "[2A", 4)
        call assert_equal_int(grid%cursor_row, 3, "Should move up 2 rows")
        call assert_equal_int(grid%cursor_col, 10, "Column should not change")
        call test_end()

        call test_begin("Cursor - CUD (Cursor Down)")
        call grid%clear()
        call parser%reset()
        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 3 B - move down 3 rows
        call parser%process_buffer(grid, char(27) // "[3B", 4)
        call assert_equal_int(grid%cursor_row, 8, "Should move down 3 rows")
        call test_end()

        call test_begin("Cursor - CUF (Cursor Forward)")
        call grid%clear()
        call parser%reset()
        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 5 C - move right 5 cols
        call parser%process_buffer(grid, char(27) // "[5C", 4)
        call assert_equal_int(grid%cursor_col, 15, "Should move right 5 cols")
        call test_end()

        call test_begin("Cursor - CUB (Cursor Back)")
        call grid%clear()
        call parser%reset()
        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 4 D - move left 4 cols
        call parser%process_buffer(grid, char(27) // "[4D", 4)
        call assert_equal_int(grid%cursor_col, 6, "Should move left 4 cols")
        call test_end()

        call test_begin("Cursor - CUP (Cursor Position)")
        call grid%clear()
        call parser%reset()

        ! ESC [ 10 ; 20 H - move to row 10, col 20
        call parser%process_buffer(grid, char(27) // "[10;20H", 8)
        call assert_equal_int(grid%cursor_row, 10, "Should move to row 10")
        call assert_equal_int(grid%cursor_col, 20, "Should move to col 20")
        call test_end()

        call test_begin("Cursor - CUP with only row")
        call grid%clear()
        call parser%reset()

        ! ESC [ 5 H - move to row 5, col 1
        call parser%process_buffer(grid, char(27) // "[5H", 4)
        call assert_equal_int(grid%cursor_row, 5, "Should move to row 5")
        call assert_equal_int(grid%cursor_col, 1, "Should default to col 1")
        call test_end()

        call test_begin("Cursor - Home position")
        call grid%clear()
        call parser%reset()
        grid%cursor_row = 10
        grid%cursor_col = 20

        ! ESC [ H - move to home (1,1)
        call parser%process_buffer(grid, char(27) // "[H", 3)
        call assert_equal_int(grid%cursor_row, 1, "Should move to row 1")
        call assert_equal_int(grid%cursor_col, 1, "Should move to col 1")
        call test_end()
    end subroutine test_cursor_movement

    ! ========================================
    ! Test erase display (ED) sequences
    ! ========================================
    subroutine test_erase_display()
        integer :: row, col

        call test_begin("ED - Clear from cursor to end (CSI J)")
        call grid%clear()
        call parser%reset()

        ! Fill grid with 'X'
        do row = 1, grid%rows
            do col = 1, grid%cols
                call grid%set_cell(row, col, ichar('X'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        end do

        ! Position cursor at row 5, col 10
        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ J (or ESC [ 0 J) - clear from cursor to end
        call parser%process_buffer(grid, char(27) // "[J", 3)

        ! Check that cells before cursor are still 'X'
        call assert_equal_int(get_cp(5, 9), ichar('X'), "Cell before cursor should be 'X'")

        ! Check that cell at cursor and after are cleared
        call assert_equal_int(get_cp(5, 10), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 11), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(6, 1), 32, "Cell should be space (cleared)")
        call test_end()

        call test_begin("ED - Clear from beginning to cursor (CSI 1 J)")
        call grid%clear()
        call parser%reset()

        ! Fill grid with 'Y'
        do row = 1, grid%rows
            do col = 1, grid%cols
                call grid%set_cell(row, col, ichar('Y'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        end do

        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 1 J - clear from beginning to cursor
        call parser%process_buffer(grid, char(27) // "[1J", 4)

        call assert_equal_int(get_cp(4, 1), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 10), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 11), ichar('Y'), "Cell after cursor should be 'Y'")
        call test_end()

        call test_begin("ED - Clear entire screen (CSI 2 J)")
        call grid%clear()
        call parser%reset()

        ! Fill grid with 'Z'
        do row = 1, grid%rows
            do col = 1, grid%cols
                call grid%set_cell(row, col, ichar('Z'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
            end do
        end do

        ! ESC [ 2 J - clear entire screen
        call parser%process_buffer(grid, char(27) // "[2J", 4)

        call assert_equal_int(get_cp(1, 1), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(12, 40), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(24, 80), 32, "Cell should be space (cleared)")
        call test_end()
    end subroutine test_erase_display

    ! ========================================
    ! Test erase line (EL) sequences
    ! ========================================
    subroutine test_erase_line()
        integer :: col

        call test_begin("EL - Clear from cursor to end of line (CSI K)")
        call grid%clear()
        call parser%reset()

        ! Fill row with 'A'
        do col = 1, grid%cols
            call grid%set_cell(5, col, ichar('A'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
        end do

        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ K - clear from cursor to end of line
        call parser%process_buffer(grid, char(27) // "[K", 3)

        call assert_equal_int(get_cp(5, 9), ichar('A'), "Before cursor should be 'A'")
        call assert_equal_int(get_cp(5, 10), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 11), 32, "Cell should be space (cleared)")
        call test_end()

        call test_begin("EL - Clear from beginning to cursor (CSI 1 K)")
        call grid%clear()
        call parser%reset()

        do col = 1, grid%cols
            call grid%set_cell(5, col, ichar('B'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
        end do

        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 1 K - clear from beginning to cursor
        call parser%process_buffer(grid, char(27) // "[1K", 4)

        call assert_equal_int(get_cp(5, 9), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 10), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 11), ichar('B'), "After cursor should be 'B'")
        call test_end()

        call test_begin("EL - Clear entire line (CSI 2 K)")
        call grid%clear()
        call parser%reset()

        do col = 1, grid%cols
            call grid%set_cell(5, col, ichar('C'), COLOR_DEFAULT, COLOR_DEFAULT, 0)
        end do

        grid%cursor_row = 5
        grid%cursor_col = 10

        ! ESC [ 2 K - clear entire line
        call parser%process_buffer(grid, char(27) // "[2K", 4)

        call assert_equal_int(get_cp(5, 1), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 40), 32, "Cell should be space (cleared)")
        call assert_equal_int(get_cp(5, 80), 32, "Cell should be space (cleared)")
        call test_end()
    end subroutine test_erase_line

    ! ========================================
    ! Test SGR color sequences
    ! ========================================
    subroutine test_sgr_colors()
        call test_begin("SGR - Foreground color (red)")
        call grid%clear()
        call parser%reset()

        ! ESC [ 31 m - red foreground
        call parser%process_buffer(grid, char(27) // "[31m", 5)
        call assert_equal_int(parser%current_fg, 1, "Foreground should be red (color 1)")
        call test_end()

        call test_begin("SGR - Background color (blue)")
        call grid%clear()
        call parser%reset()

        ! ESC [ 44 m - blue background
        call parser%process_buffer(grid, char(27) // "[44m", 5)
        call assert_equal_int(parser%current_bg, 4, "Background should be blue (color 4)")
        call test_end()

        call test_begin("SGR - Bright foreground (bright green)")
        call grid%clear()
        call parser%reset()

        ! ESC [ 92 m - bright green foreground
        call parser%process_buffer(grid, char(27) // "[92m", 5)
        call assert_equal_int(parser%current_fg, 10, "Foreground should be bright green (color 10)")
        call test_end()

        call test_begin("SGR - Multiple attributes (red fg + blue bg)")
        call grid%clear()
        call parser%reset()

        ! ESC [ 31 ; 44 m - red fg, blue bg
        call parser%process_buffer(grid, char(27) // "[31;44m", 8)
        call assert_equal_int(parser%current_fg, 1, "Foreground should be red")
        call assert_equal_int(parser%current_bg, 4, "Background should be blue")
        call test_end()

        call test_begin("SGR - Reset (CSI m)")
        call grid%clear()
        call parser%reset()

        ! Set colors
        call parser%process_buffer(grid, char(27) // "[31;44m", 8)
        ! Reset
        call parser%process_buffer(grid, char(27) // "[m", 3)
        call assert_equal_int(parser%current_fg, COLOR_DEFAULT, "Foreground should be reset")
        call assert_equal_int(parser%current_bg, COLOR_DEFAULT, "Background should be reset")
        call test_end()

        call test_begin("SGR - Explicit reset (CSI 0 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[31;44m", 8)
        call parser%process_buffer(grid, char(27) // "[0m", 4)
        call assert_equal_int(parser%current_fg, COLOR_DEFAULT, "Foreground should be reset")
        call assert_equal_int(parser%current_bg, COLOR_DEFAULT, "Background should be reset")
        call test_end()
    end subroutine test_sgr_colors

    ! ========================================
    ! Test SGR attribute sequences (bold, italic, etc.)
    ! ========================================
    subroutine test_sgr_attributes()
        call test_begin("SGR - Bold (CSI 1 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[1m", 4)
        call assert_true(iand(parser%current_attrs, ATTR_BOLD) /= 0, "Bold should be set")
        call test_end()

        call test_begin("SGR - Italic (CSI 3 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[3m", 4)
        call assert_true(iand(parser%current_attrs, ATTR_ITALIC) /= 0, "Italic should be set")
        call test_end()

        call test_begin("SGR - Underline (CSI 4 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[4m", 4)
        call assert_true(iand(parser%current_attrs, ATTR_UNDERLINE) /= 0, "Underline should be set")
        call test_end()

        call test_begin("SGR - Reverse (CSI 7 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[7m", 4)
        call assert_true(iand(parser%current_attrs, ATTR_REVERSE) /= 0, "Reverse should be set")
        call test_end()

        call test_begin("SGR - Turn off bold (CSI 22 m)")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[1m", 4)  ! Set bold
        call parser%process_buffer(grid, char(27) // "[22m", 5)  ! Turn off bold
        call assert_true(iand(parser%current_attrs, ATTR_BOLD) == 0, "Bold should be turned off")
        call test_end()

        call test_begin("SGR - Combined attributes")
        call grid%clear()
        call parser%reset()

        ! ESC [ 1 ; 3 ; 4 m - bold, italic, underline
        call parser%process_buffer(grid, char(27) // "[1;3;4m", 8)
        call assert_true(iand(parser%current_attrs, ATTR_BOLD) /= 0, "Bold should be set")
        call assert_true(iand(parser%current_attrs, ATTR_ITALIC) /= 0, "Italic should be set")
        call assert_true(iand(parser%current_attrs, ATTR_UNDERLINE) /= 0, "Underline should be set")
        call test_end()
    end subroutine test_sgr_attributes

    ! ========================================
    ! Test state machine transitions
    ! ========================================
    subroutine test_state_machine()
        call test_begin("State - Ground to Escape")
        call grid%clear()
        call parser%reset()

        call assert_equal_int(parser%state, STATE_GROUND, "Should start in GROUND state")
        call parser%process_byte(grid, 27)  ! ESC
        call assert_equal_int(parser%state, STATE_ESCAPE, "Should transition to ESCAPE state")
        call test_end()

        call test_begin("State - Escape to CSI Entry")
        call grid%clear()
        call parser%reset()

        call parser%process_byte(grid, 27)  ! ESC
        call parser%process_byte(grid, ichar('['))  ! [
        call assert_equal_int(parser%state, STATE_CSI_ENTRY, "Should transition to CSI_ENTRY state")
        call test_end()

        call test_begin("State - CSI sequence completes to Ground")
        call grid%clear()
        call parser%reset()

        call parser%process_buffer(grid, char(27) // "[H", 3)
        call assert_equal_int(parser%state, STATE_GROUND, "Should return to GROUND after complete CSI")
        call test_end()

        call test_begin("State - OSC sequence handling")
        call grid%clear()
        call parser%reset()

        call parser%process_byte(grid, 27)  ! ESC
        call parser%process_byte(grid, ichar(']'))  ! ]
        call assert_equal_int(parser%state, STATE_OSC_STRING, "Should transition to OSC_STRING state")

        ! OSC terminated by BEL
        call parser%process_byte(grid, 7)  ! BEL
        call assert_equal_int(parser%state, STATE_GROUND, "Should return to GROUND after BEL")
        call test_end()

        call test_begin("State - DCS sequence handling")
        call grid%clear()
        call parser%reset()

        call parser%process_byte(grid, 27)  ! ESC
        call parser%process_byte(grid, ichar('P'))  ! P
        call assert_equal_int(parser%state, STATE_DCS_STRING, "Should transition to DCS_STRING state")

        ! DCS terminated by BEL
        call parser%process_byte(grid, 7)  ! BEL
        call assert_equal_int(parser%state, STATE_GROUND, "Should return to GROUND after BEL")
        call test_end()
    end subroutine test_state_machine

end program test_vt_parser
