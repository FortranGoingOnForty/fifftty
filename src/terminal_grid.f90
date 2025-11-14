module terminal_grid
    use, intrinsic :: iso_c_binding
    implicit none
    private

    ! Cell attributes (bitflags)
    integer, parameter, public :: ATTR_BOLD       = ishft(1, 0)
    integer, parameter, public :: ATTR_ITALIC     = ishft(1, 1)
    integer, parameter, public :: ATTR_UNDERLINE  = ishft(1, 2)
    integer, parameter, public :: ATTR_BLINK      = ishft(1, 3)
    integer, parameter, public :: ATTR_REVERSE    = ishft(1, 4)
    integer, parameter, public :: ATTR_HIDDEN     = ishft(1, 5)
    integer, parameter, public :: ATTR_STRIKETHROUGH = ishft(1, 6)

    ! ANSI color indices (16-color palette for Phase 1)
    integer, parameter, public :: COLOR_BLACK   = 0
    integer, parameter, public :: COLOR_RED     = 1
    integer, parameter, public :: COLOR_GREEN   = 2
    integer, parameter, public :: COLOR_YELLOW  = 3
    integer, parameter, public :: COLOR_BLUE    = 4
    integer, parameter, public :: COLOR_MAGENTA = 5
    integer, parameter, public :: COLOR_CYAN    = 6
    integer, parameter, public :: COLOR_WHITE   = 7
    integer, parameter, public :: COLOR_DEFAULT = 256  ! Use terminal default

    ! Bright colors (8-15)
    integer, parameter, public :: COLOR_BRIGHT_BLACK   = 8
    integer, parameter, public :: COLOR_BRIGHT_RED     = 9
    integer, parameter, public :: COLOR_BRIGHT_GREEN   = 10
    integer, parameter, public :: COLOR_BRIGHT_YELLOW  = 11
    integer, parameter, public :: COLOR_BRIGHT_BLUE    = 12
    integer, parameter, public :: COLOR_BRIGHT_MAGENTA = 13
    integer, parameter, public :: COLOR_BRIGHT_CYAN    = 14
    integer, parameter, public :: COLOR_BRIGHT_WHITE   = 15

    ! Terminal cell - represents one character position
    type, public :: cell_t
        integer :: codepoint      ! Unicode codepoint (UTF-32)
        integer :: fg_color       ! Foreground color index
        integer :: bg_color       ! Background color index
        integer :: attributes     ! Bitfield of ATTR_* flags
    end type cell_t

    ! Terminal grid - the main buffer
    type, public :: grid_t
        integer :: rows           ! Number of rows
        integer :: cols           ! Number of columns
        integer :: cursor_row     ! Cursor position (1-indexed)
        integer :: cursor_col     ! Cursor position (1-indexed)
        logical :: cursor_visible ! Cursor visibility
        logical :: pending_wrap   ! True if cursor is at rightmost column and next char will wrap
        type(cell_t), allocatable :: cells(:,:)  ! Grid buffer (col, row)
        ! Scrollback history
        type(cell_t), allocatable :: history(:,:)  ! History buffer (col, line)
        integer :: history_size = 10000            ! Maximum history lines
        integer :: history_start = 1               ! Index of oldest line (circular buffer)
        integer :: history_count = 0               ! Number of lines in history
        integer :: scroll_offset = 0               ! How far back we're viewing (0 = current)
        ! Scrolling region (DECSTBM)
        integer :: scroll_top = 1                  ! Top margin (1-indexed)
        integer :: scroll_bottom = 0               ! Bottom margin (0 = use rows)
        ! Alternate screen buffer
        type(cell_t), allocatable :: alt_cells(:,:)  ! Alternate screen buffer
        logical :: use_alt_screen = .false.          ! True if alternate screen is active
        integer :: saved_cursor_row = 1              ! Saved cursor position
        integer :: saved_cursor_col = 1
        ! Text selection
        logical :: selection_active = .false.        ! True if text is selected
        integer :: selection_start_row = 1           ! Selection start position
        integer :: selection_start_col = 1
        integer :: selection_end_row = 1             ! Selection end position
        integer :: selection_end_col = 1
    contains
        procedure :: init => grid_init
        procedure :: destroy => grid_destroy
        procedure :: clear => grid_clear
        procedure :: clear_line => grid_clear_line
        procedure :: set_cell => grid_set_cell
        procedure :: get_cell => grid_get_cell
        procedure :: scroll_up => grid_scroll_up
        procedure :: resize => grid_resize
        procedure :: move_cursor => grid_move_cursor
        procedure :: scroll_back => grid_scroll_back
        procedure :: scroll_forward => grid_scroll_forward
        procedure :: scroll_to_top => grid_scroll_to_top
        procedure :: scroll_to_bottom => grid_scroll_to_bottom
        procedure :: get_history_line => grid_get_history_line
        procedure :: insert_chars => grid_insert_chars
        procedure :: delete_chars => grid_delete_chars
        procedure :: insert_lines => grid_insert_lines
        procedure :: delete_lines => grid_delete_lines
        procedure :: set_scroll_region => grid_set_scroll_region
        procedure :: switch_to_alt_screen => grid_switch_to_alt_screen
        procedure :: switch_to_main_screen => grid_switch_to_main_screen
        procedure :: set_selection_start => grid_set_selection_start
        procedure :: set_selection_end => grid_set_selection_end
        procedure :: clear_selection => grid_clear_selection
        procedure :: is_cell_selected => grid_is_cell_selected
    end type grid_t

contains

    ! Initialize grid with given dimensions
    subroutine grid_init(this, rows, cols)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: rows, cols

        this%rows = rows
        this%cols = cols
        this%cursor_row = 1
        this%cursor_col = 1
        this%cursor_visible = .true.
        this%pending_wrap = .false.

        allocate(this%cells(cols, rows))
        call this%clear()

        ! Allocate alternate screen buffer
        allocate(this%alt_cells(cols, rows))
        this%use_alt_screen = .false.

        ! Allocate scrollback history buffer
        allocate(this%history(cols, this%history_size))
        this%history_start = 1
        this%history_count = 0
        this%scroll_offset = 0

        ! Initialize scrolling region to full screen
        this%scroll_top = 1
        this%scroll_bottom = rows
    end subroutine grid_init

    ! Destroy grid and free memory
    subroutine grid_destroy(this)
        class(grid_t), intent(inout) :: this
        if (allocated(this%cells)) deallocate(this%cells)
        if (allocated(this%alt_cells)) deallocate(this%alt_cells)
        if (allocated(this%history)) deallocate(this%history)
    end subroutine grid_destroy

    ! Clear entire grid
    subroutine grid_clear(this)
        class(grid_t), intent(inout) :: this
        integer :: i, j

        do j = 1, this%rows
            do i = 1, this%cols
                this%cells(i, j)%codepoint = 32  ! Space character
                this%cells(i, j)%fg_color = COLOR_DEFAULT
                this%cells(i, j)%bg_color = COLOR_DEFAULT
                this%cells(i, j)%attributes = 0
            end do
        end do

        ! Reset cursor to home position
        this%cursor_row = 1
        this%cursor_col = 1
        this%pending_wrap = .false.
    end subroutine grid_clear

    ! Clear a single line
    subroutine grid_clear_line(this, row)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: row
        integer :: i

        if (row < 1 .or. row > this%rows) return

        do i = 1, this%cols
            this%cells(i, row)%codepoint = 32
            this%cells(i, row)%fg_color = COLOR_DEFAULT
            this%cells(i, row)%bg_color = COLOR_DEFAULT
            this%cells(i, row)%attributes = 0
        end do
    end subroutine grid_clear_line

    ! Set a cell at given position
    subroutine grid_set_cell(this, row, col, codepoint, fg, bg, attrs)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: row, col, codepoint
        integer, intent(in), optional :: fg, bg, attrs

        if (row < 1 .or. row > this%rows) return
        if (col < 1 .or. col > this%cols) return

        if (this%use_alt_screen) then
            this%alt_cells(col, row)%codepoint = codepoint
            if (present(fg)) this%alt_cells(col, row)%fg_color = fg
            if (present(bg)) this%alt_cells(col, row)%bg_color = bg
            if (present(attrs)) this%alt_cells(col, row)%attributes = attrs
        else
            this%cells(col, row)%codepoint = codepoint
            if (present(fg)) this%cells(col, row)%fg_color = fg
            if (present(bg)) this%cells(col, row)%bg_color = bg
            if (present(attrs)) this%cells(col, row)%attributes = attrs
        end if
    end subroutine grid_set_cell

    ! Get a cell at given position
    function grid_get_cell(this, row, col) result(cell)
        class(grid_t), intent(in) :: this
        integer, intent(in) :: row, col
        type(cell_t) :: cell

        ! Return default cell if out of bounds
        if (row < 1 .or. row > this%rows .or. col < 1 .or. col > this%cols) then
            cell%codepoint = 32
            cell%fg_color = COLOR_DEFAULT
            cell%bg_color = COLOR_DEFAULT
            cell%attributes = 0
            return
        end if

        if (this%use_alt_screen) then
            cell = this%alt_cells(col, row)
        else
            cell = this%cells(col, row)
        end if
    end function grid_get_cell

    ! Scroll the grid up by one line (insert blank line at bottom of scroll region)
    subroutine grid_scroll_up(this)
        class(grid_t), intent(inout) :: this
        integer :: row, history_idx, region_bottom

        region_bottom = this%scroll_bottom
        if (region_bottom <= 0) region_bottom = this%rows

        ! Only save to history if scrolling from top of screen
        if (this%scroll_top == 1) then
            if (this%history_count < this%history_size) then
                ! History not full yet, add to end
                history_idx = this%history_count + 1
                this%history(:, history_idx) = this%cells(:, this%scroll_top)
                this%history_count = this%history_count + 1
            else
                ! History full, use circular buffer (overwrite oldest)
                history_idx = this%history_start
                this%history(:, history_idx) = this%cells(:, this%scroll_top)
                ! Move start pointer forward (circular)
                this%history_start = mod(this%history_start, this%history_size) + 1
            end if
        end if

        ! Shift rows up within the scroll region
        do row = this%scroll_top, region_bottom - 1
            this%cells(:, row) = this%cells(:, row + 1)
        end do

        ! Clear bottom row of scroll region
        call this%clear_line(region_bottom)

        ! Reset scroll offset when new content arrives
        this%scroll_offset = 0
    end subroutine grid_scroll_up

    ! Resize grid (creates new buffer, copies old content)
    subroutine grid_resize(this, new_rows, new_cols)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: new_rows, new_cols
        type(cell_t), allocatable :: old_cells(:,:)
        integer :: copy_rows, copy_cols, i, j
        integer :: old_rows, old_cols

        ! Save old dimensions
        old_rows = this%rows
        old_cols = this%cols

        ! Save old cells
        allocate(old_cells(this%cols, this%rows))
        old_cells = this%cells

        ! Deallocate and reallocate with new size
        deallocate(this%cells)
        allocate(this%cells(new_cols, new_rows))

        ! Update dimensions BEFORE clearing (grid_clear uses this%rows/cols!)
        this%rows = new_rows
        this%cols = new_cols

        ! Clear new grid first
        call this%clear()

        ! Determine how much to copy (using saved old dimensions)
        copy_rows = min(old_rows, new_rows)
        copy_cols = min(old_cols, new_cols)

        ! Copy old content
        do j = 1, copy_rows
            do i = 1, copy_cols
                this%cells(i, j) = old_cells(i, j)
            end do
        end do

        ! Clamp cursor to new bounds
        if (this%cursor_row > new_rows) this%cursor_row = new_rows
        if (this%cursor_col > new_cols) this%cursor_col = new_cols

        deallocate(old_cells)
    end subroutine grid_resize

    ! Move cursor to position (clamps to grid bounds)
    subroutine grid_move_cursor(this, row, col)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: row, col

        this%cursor_row = max(1, min(row, this%rows))
        this%cursor_col = max(1, min(col, this%cols))
        this%pending_wrap = .false.  ! Clear pending wrap on explicit cursor movement
    end subroutine grid_move_cursor

    ! Scroll back in history (increase scroll offset)
    subroutine grid_scroll_back(this, lines)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: lines

        this%scroll_offset = min(this%scroll_offset + lines, this%history_count)
    end subroutine grid_scroll_back

    ! Scroll forward towards current (decrease scroll offset)
    subroutine grid_scroll_forward(this, lines)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: lines

        this%scroll_offset = max(this%scroll_offset - lines, 0)
    end subroutine grid_scroll_forward

    ! Scroll to top of history
    subroutine grid_scroll_to_top(this)
        class(grid_t), intent(inout) :: this

        this%scroll_offset = this%history_count
    end subroutine grid_scroll_to_top

    ! Scroll to bottom (current view)
    subroutine grid_scroll_to_bottom(this)
        class(grid_t), intent(inout) :: this

        this%scroll_offset = 0
    end subroutine grid_scroll_to_bottom

    ! Get a line from history (returns cells for that line)
    ! line_num is relative to current view: 1 = oldest visible, history_count = newest in history
    function grid_get_history_line(this, line_num) result(line)
        class(grid_t), intent(in) :: this
        integer, intent(in) :: line_num
        type(cell_t), allocatable :: line(:)
        integer :: history_idx

        allocate(line(this%cols))

        ! Calculate actual index in circular buffer
        if (this%history_count < this%history_size) then
            ! History not full, simple indexing
            history_idx = line_num
        else
            ! History full, use circular indexing
            history_idx = mod(this%history_start + line_num - 2, this%history_size) + 1
        end if

        line = this%history(:, history_idx)
    end function grid_get_history_line

    ! Insert n blank characters at cursor position (ICH - Insert Character)
    ! Characters from cursor to right edge shift right, rightmost chars are lost
    subroutine grid_insert_chars(this, count)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: count
        integer :: i, n, row, start_col

        row = this%cursor_row
        start_col = this%cursor_col
        n = min(count, this%cols - start_col + 1)  ! Don't insert more than will fit

        ! Shift characters right from end to cursor position
        do i = this%cols, start_col + n, -1
            if (i - n >= start_col) then
                this%cells(i, row) = this%cells(i - n, row)
            end if
        end do

        ! Fill inserted positions with blanks
        do i = start_col, min(start_col + n - 1, this%cols)
            this%cells(i, row)%codepoint = 32
            this%cells(i, row)%fg_color = COLOR_DEFAULT
            this%cells(i, row)%bg_color = COLOR_DEFAULT
            this%cells(i, row)%attributes = 0
        end do
    end subroutine grid_insert_chars

    ! Delete n characters at cursor position (DCH - Delete Character)
    ! Characters to the right of deleted area shift left, blanks fill right edge
    subroutine grid_delete_chars(this, count)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: count
        integer :: i, n, row, start_col

        row = this%cursor_row
        start_col = this%cursor_col
        n = min(count, this%cols - start_col + 1)  ! Don't delete more than available

        ! Shift characters left
        do i = start_col, this%cols - n
            this%cells(i, row) = this%cells(i + n, row)
        end do

        ! Fill right edge with blanks
        do i = this%cols - n + 1, this%cols
            this%cells(i, row)%codepoint = 32
            this%cells(i, row)%fg_color = COLOR_DEFAULT
            this%cells(i, row)%bg_color = COLOR_DEFAULT
            this%cells(i, row)%attributes = 0
        end do
    end subroutine grid_delete_chars

    ! Insert n blank lines at cursor position (IL - Insert Line)
    ! Lines from cursor row down shift down within scroll region, bottom lines are lost
    subroutine grid_insert_lines(this, count)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: count
        integer :: i, n, start_row, region_bottom

        start_row = this%cursor_row
        region_bottom = this%scroll_bottom
        if (region_bottom <= 0) region_bottom = this%rows
        n = min(count, region_bottom - start_row + 1)  ! Don't insert more than will fit

        ! Shift lines down from bottom of region to cursor position
        do i = region_bottom, start_row + n, -1
            if (i - n >= start_row) then
                this%cells(:, i) = this%cells(:, i - n)
            end if
        end do

        ! Fill inserted lines with blanks
        do i = start_row, min(start_row + n - 1, region_bottom)
            call this%clear_line(i)
        end do
    end subroutine grid_insert_lines

    ! Delete n lines at cursor position (DL - Delete Line)
    ! Lines below cursor shift up within scroll region, blank lines fill bottom
    subroutine grid_delete_lines(this, count)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: count
        integer :: i, n, start_row, region_bottom

        start_row = this%cursor_row
        region_bottom = this%scroll_bottom
        if (region_bottom <= 0) region_bottom = this%rows
        n = min(count, region_bottom - start_row + 1)  ! Don't delete more than available

        ! Shift lines up within region
        do i = start_row, region_bottom - n
            this%cells(:, i) = this%cells(:, i + n)
        end do

        ! Fill bottom of region with blank lines
        do i = region_bottom - n + 1, region_bottom
            call this%clear_line(i)
        end do
    end subroutine grid_delete_lines

    ! Set scrolling region (DECSTBM)
    subroutine grid_set_scroll_region(this, top, bottom)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: top, bottom

        ! Validate and set scroll region
        if (top >= 1 .and. bottom <= this%rows .and. top < bottom) then
            this%scroll_top = top
            this%scroll_bottom = bottom
        else if (top == 0 .and. bottom == 0) then
            ! Reset to full screen
            this%scroll_top = 1
            this%scroll_bottom = this%rows
        end if
    end subroutine grid_set_scroll_region

    ! Switch to alternate screen buffer (ESC[?1049h)
    ! Saves cursor position, clears alt screen, switches to it
    subroutine grid_switch_to_alt_screen(this)
        class(grid_t), intent(inout) :: this

        if (this%use_alt_screen) return  ! Already on alt screen

        ! Save cursor position
        this%saved_cursor_row = this%cursor_row
        this%saved_cursor_col = this%cursor_col

        ! Switch to alternate screen
        this%use_alt_screen = .true.

        ! Clear alternate screen
        this%alt_cells = this%cells  ! Copy current state first (optional)
        call clear_buffer(this%alt_cells, this%cols, this%rows)

        ! Move cursor to home
        this%cursor_row = 1
        this%cursor_col = 1
    end subroutine grid_switch_to_alt_screen

    ! Switch back to main screen buffer (ESC[?1049l)
    ! Restores cursor position, switches back to main screen
    subroutine grid_switch_to_main_screen(this)
        class(grid_t), intent(inout) :: this

        if (.not. this%use_alt_screen) return  ! Already on main screen

        ! Switch back to main screen
        this%use_alt_screen = .false.

        ! Restore cursor position
        this%cursor_row = this%saved_cursor_row
        this%cursor_col = this%saved_cursor_col
    end subroutine grid_switch_to_main_screen

    ! Helper to clear a buffer
    subroutine clear_buffer(buffer, cols, rows)
        type(cell_t), intent(inout) :: buffer(:,:)
        integer, intent(in) :: cols, rows
        integer :: i, j

        do j = 1, rows
            do i = 1, cols
                buffer(i, j)%codepoint = 32
                buffer(i, j)%fg_color = COLOR_DEFAULT
                buffer(i, j)%bg_color = COLOR_DEFAULT
                buffer(i, j)%attributes = 0
            end do
        end do
    end subroutine clear_buffer

    ! Set selection start position (mouse button press)
    subroutine grid_set_selection_start(this, row, col)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: row, col

        this%selection_active = .true.
        this%selection_start_row = row
        this%selection_start_col = col
        this%selection_end_row = row
        this%selection_end_col = col
    end subroutine grid_set_selection_start

    ! Set selection end position (mouse drag)
    subroutine grid_set_selection_end(this, row, col)
        class(grid_t), intent(inout) :: this
        integer, intent(in) :: row, col

        if (.not. this%selection_active) return

        this%selection_end_row = row
        this%selection_end_col = col
    end subroutine grid_set_selection_end

    ! Clear selection
    subroutine grid_clear_selection(this)
        class(grid_t), intent(inout) :: this

        this%selection_active = .false.
        this%selection_start_row = 1
        this%selection_start_col = 1
        this%selection_end_row = 1
        this%selection_end_col = 1
    end subroutine grid_clear_selection

    ! Check if a cell is within the selected region
    function grid_is_cell_selected(this, row, col) result(selected)
        class(grid_t), intent(in) :: this
        integer, intent(in) :: row, col
        logical :: selected
        integer :: start_row, start_col, end_row, end_col
        integer :: cell_pos, start_pos, end_pos

        selected = .false.

        if (.not. this%selection_active) return

        ! Normalize selection (start <= end)
        if (this%selection_start_row < this%selection_end_row .or. &
            (this%selection_start_row == this%selection_end_row .and. &
             this%selection_start_col <= this%selection_end_col)) then
            start_row = this%selection_start_row
            start_col = this%selection_start_col
            end_row = this%selection_end_row
            end_col = this%selection_end_col
        else
            start_row = this%selection_end_row
            start_col = this%selection_end_col
            end_row = this%selection_start_row
            end_col = this%selection_start_col
        end if

        ! Convert to linear position for easy comparison
        cell_pos = (row - 1) * this%cols + col
        start_pos = (start_row - 1) * this%cols + start_col
        end_pos = (end_row - 1) * this%cols + end_col

        selected = (cell_pos >= start_pos .and. cell_pos <= end_pos)
    end function grid_is_cell_selected

end module terminal_grid
