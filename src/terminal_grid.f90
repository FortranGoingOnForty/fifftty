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
    end subroutine grid_init

    ! Destroy grid and free memory
    subroutine grid_destroy(this)
        class(grid_t), intent(inout) :: this
        if (allocated(this%cells)) deallocate(this%cells)
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

        this%cells(col, row)%codepoint = codepoint
        if (present(fg)) this%cells(col, row)%fg_color = fg
        if (present(bg)) this%cells(col, row)%bg_color = bg
        if (present(attrs)) this%cells(col, row)%attributes = attrs
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

        cell = this%cells(col, row)
    end function grid_get_cell

    ! Scroll the grid up by one line (insert blank line at bottom)
    subroutine grid_scroll_up(this)
        class(grid_t), intent(inout) :: this
        integer :: row

        ! Shift all rows up
        do row = 1, this%rows - 1
            this%cells(:, row) = this%cells(:, row + 1)
        end do

        ! Clear bottom row
        call this%clear_line(this%rows)
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

end module terminal_grid
