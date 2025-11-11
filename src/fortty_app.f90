module fortty_app
    use, intrinsic :: iso_c_binding
    use gtk_bindings
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

        ! Make GL context current
        call gtk_gl_area_make_current(gl_area)

        ! Initialize terminal grid (80x24 is standard)
        call global_grid%init(24, 80)

        ! Initialize VT parser
        call global_parser%reset()

        ! Find a system font (monospace)
        font_path = "/System/Library/Fonts/Monaco.dfont"  ! macOS
        ! TODO: Add Linux font paths fallback

        ! Initialize renderer
        if (.not. global_renderer%init(trim(font_path), 16, 800, 600)) then
            print *, "Error: Failed to initialize renderer"
            return
        end if

        ! Create PTY and spawn shell
        pty_success = global_pty%open(24, 80)
        if (.not. pty_success) then
            print *, "Error: Failed to open PTY"
            return
        end if

        initialized = .true.
        print *, "fortty: OpenGL and PTY initialized"

        ! Start PTY polling
        call start_pty_polling()
    end subroutine gl_realize_callback

    ! GL render callback - draw the terminal
    function gl_render_callback(gl_area, context, user_data) bind(c) result(handled)
        type(c_ptr), value :: gl_area, context, user_data
        integer(c_int) :: handled

        if (.not. initialized) then
            handled = 0  ! FALSE
            return
        end if

        ! Render the terminal grid
        call global_renderer%draw_grid(global_grid)

        handled = 1  ! TRUE - we handled the render
    end function gl_render_callback

    ! Key pressed callback - send input to PTY
    function key_pressed_callback(controller, keyval, keycode, state, user_data) &
            bind(c) result(handled)
        type(c_ptr), value :: controller, user_data
        integer(c_int), value :: keyval, keycode, state
        integer(c_int) :: handled
        character(len=16) :: key_string
        integer :: bytes_written, key_len

        handled = 0  ! FALSE by default

        if (.not. initialized) return

        ! Convert keyval to character and send to PTY
        if (keyval >= 32 .and. keyval <= 126) then
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

            ! Queue a render
            if (c_associated(global_gl_area)) then
                call gtk_gl_area_queue_render(global_gl_area)
            end if
        end if
    end function pty_poll_callback

    ! Start PTY polling with timeout
    subroutine start_pty_polling()
        integer(c_int) :: timeout_id

        ! Poll PTY every 10ms
        timeout_id = g_timeout_add(10_c_int, c_funloc(pty_poll_callback), c_null_ptr)

        if (timeout_id == 0) then
            print *, "Warning: Failed to start PTY polling"
        end if
    end subroutine start_pty_polling

end module fortty_app
