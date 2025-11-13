module fortty_app
    use, intrinsic :: iso_c_binding
    use gtk_bindings
    use opengl_bindings
    use terminal_grid
    use pty_manager
    use vt_parser
    use renderer
    implicit none

    ! Global application state (accessible to all callbacks)
    type(pty_t), save :: global_pty
    type(grid_t), save :: global_grid
    type(parser_t), save :: global_parser
    type(renderer_t), save :: global_renderer
    type(c_ptr), save :: global_gl_area = c_null_ptr
    logical, save :: initialized = .false.

contains

    ! GL realize callback - initialize OpenGL resources
    subroutine gl_realize_callback(gl_area, user_data) bind(c)
        type(c_ptr), value :: gl_area, user_data
        character(len=256) :: font_path
        logical :: pty_success

        integer :: grid_rows, grid_cols

        ! Make GL context current
        call gtk_gl_area_make_current(gl_area)

        ! Initialize VT parser
        call global_parser%reset()

        ! Find a system font (monospace)
        call find_system_font(font_path)

        ! Initialize renderer (this calculates cell dimensions)
        if (.not. global_renderer%init(trim(font_path), 16, 800, 600)) then
            print *, "Error: Failed to initialize renderer"
            return
        end if

        ! Calculate terminal grid size from window and cell dimensions
        grid_cols = 800 / global_renderer%cell_width
        grid_rows = 600 / global_renderer%cell_height

        print '(A,I0,A,I0,A,I0,A,I0)', "DEBUG: Window 800x600, cells ", &
            global_renderer%cell_width, "x", global_renderer%cell_height, &
            " -> grid ", grid_cols, "x", grid_rows

        ! Initialize terminal grid with calculated dimensions
        call global_grid%init(grid_rows, grid_cols)

        ! Create PTY and spawn shell with actual grid size
        pty_success = global_pty%open(grid_rows, grid_cols)
        if (.not. pty_success) then
            return
        end if

        ! Connect PTY to parser for bidirectional communication
        call global_parser%set_pty(global_pty)

        initialized = .true.

        ! Debug: Print initial state
        print '(A,I0,A,I0)', "DEBUG: Terminal initialized with cursor at ", &
              global_grid%cursor_row, ",", global_grid%cursor_col

        ! Start PTY polling
        call start_pty_polling()
    end subroutine gl_realize_callback

    ! GL render callback - draw the terminal
    function gl_render_callback(gl_area, context, user_data) bind(c) result(handled)
        type(c_ptr), value :: gl_area, context, user_data
        integer(c_int) :: handled

        handled = 1  ! TRUE

        if (.not. initialized) return

        ! Make GL context current
        call gtk_gl_area_make_current(gl_area)

        ! Render the terminal grid
        call global_renderer%draw_grid(global_grid)
    end function gl_render_callback

    ! Key pressed callback - send input to PTY
    function key_pressed_callback(controller, keyval, keycode, state, user_data) &
            bind(c) result(handled)
        type(c_ptr), value :: controller, user_data
        integer(c_int), value :: keyval, keycode, state
        integer(c_int) :: handled
        character(len=16) :: key_string
        integer :: bytes_written, key_len
        integer, parameter :: GDK_CONTROL_MASK = 4  ! Ctrl modifier

        handled = 0  ! FALSE by default

        if (.not. initialized) return

        ! Check for Ctrl+letter combinations (Ctrl+A through Ctrl+Z)
        ! GTK sends lowercase letters with Ctrl modifier
        if (iand(state, GDK_CONTROL_MASK) /= 0) then
            ! Ctrl is pressed
            if (keyval >= ichar('a') .and. keyval <= ichar('z')) then
                ! Ctrl+A = 1, Ctrl+B = 2, ..., Ctrl+Z = 26
                key_string(1:1) = char(keyval - ichar('a') + 1)
                key_len = 1
            else if (keyval >= ichar('A') .and. keyval <= ichar('Z')) then
                ! Handle uppercase too (though GTK usually sends lowercase)
                key_string(1:1) = char(keyval - ichar('A') + 1)
                key_len = 1
            else
                return  ! Other Ctrl combinations not handled
            end if
        ! Convert keyval to character and send to PTY
        else if (keyval >= 32 .and. keyval <= 126) then
            key_string(1:1) = char(keyval)
            key_len = 1
        else if (keyval == 65293) then  ! Return/Enter
            key_string(1:1) = char(13)  ! CR
            key_len = 1
        else if (keyval == 65288) then  ! Backspace
            key_string(1:1) = char(127)  ! DEL
            key_len = 1
        else if (keyval == 65289) then  ! Tab
            key_string(1:1) = char(9)
            key_len = 1
        else if (keyval == 65307) then  ! Escape
            key_string(1:1) = char(27)
            key_len = 1
        else if (keyval == 65362) then  ! Up arrow
            key_string(1:3) = char(27) // "[A"
            key_len = 3
        else if (keyval == 65364) then  ! Down arrow
            key_string(1:3) = char(27) // "[B"
            key_len = 3
        else if (keyval == 65363) then  ! Right arrow
            key_string(1:3) = char(27) // "[C"
            key_len = 3
        else if (keyval == 65361) then  ! Left arrow
            key_string(1:3) = char(27) // "[D"
            key_len = 3
        else
            return
        end if

        ! Send to PTY
        bytes_written = global_pty%write(key_string, key_len)
        if (bytes_written > 0) then
            handled = 1  ! TRUE
        end if
    end function key_pressed_callback

    ! PTY poll callback - read from PTY and update terminal
    function pty_poll_callback(user_data) bind(c) result(continue)
        type(c_ptr), value :: user_data
        integer(c_int) :: continue
        character(len=4096) :: buffer
        integer :: bytes_read

        continue = 1  ! TRUE - continue calling

        if (.not. initialized) return

        ! Read from PTY
        bytes_read = global_pty%read(buffer, 4096)

        if (bytes_read > 0) then
            ! Process data through VT parser
            call global_parser%process_buffer(global_grid, buffer, bytes_read)
            ! Request GL render for GtkGLArea (more direct than queue_draw)
            call gtk_gl_area_queue_render(global_gl_area)
        end if
    end function pty_poll_callback

    ! Start PTY polling with timeout
    subroutine start_pty_polling()
        integer(c_int) :: timeout_id

        ! Poll PTY every 10ms
        timeout_id = g_timeout_add(10_c_int, c_funloc(pty_poll_callback), c_null_ptr)

        if (timeout_id == 0) then
            print *, "Error: Failed to start PTY polling"
        end if
    end subroutine start_pty_polling

    ! Find a monospace system font
    subroutine find_system_font(font_path)
        character(len=*), intent(out) :: font_path
        logical :: file_exists
        character(len=256), dimension(5) :: font_candidates
        integer :: i

        ! List of common monospace font locations (in priority order)
        font_candidates(1) = "/System/Library/Fonts/Menlo.ttc"                 ! macOS (scalable)
        font_candidates(2) = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"  ! Linux
        font_candidates(3) = "/usr/share/fonts/TTF/DejaVuSansMono.ttf"        ! Arch Linux
        font_candidates(4) = "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf"  ! RHEL/Fedora
        font_candidates(5) = "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"  ! Ubuntu

        ! Try each font location
        do i = 1, size(font_candidates)
            inquire(file=trim(font_candidates(i)), exist=file_exists)
            if (file_exists) then
                font_path = font_candidates(i)
                return
            end if
        end do

        ! No font found - use first as fallback
        font_path = font_candidates(1)
    end subroutine find_system_font

end module fortty_app
