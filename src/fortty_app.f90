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
    type(c_ptr), save :: global_window = c_null_ptr
    logical, save :: initialized = .false.
    logical, save :: mapped = .false.
    integer, save :: pending_width = 0
    integer, save :: pending_height = 0
    character(len=256), save :: last_window_title = "fortty"
    logical, save :: mouse_button_pressed = .false.

contains

    ! GL realize callback - initialize OpenGL resources
    subroutine gl_realize_callback(gl_area, user_data) bind(c)
        type(c_ptr), value :: gl_area, user_data

        ! Make GL context current
        call gtk_gl_area_make_current(gl_area)

        print '(A)', "DEBUG: GL realize callback - OpenGL context ready"
        print '(A)', "DEBUG: Deferring initialization until first resize event..."

        ! Don't initialize here! The widget hasn't been allocated a size yet.
        ! We'll initialize in the resize callback when we get the actual size.
        ! This handles the case where the window auto-snaps to a different monitor
        ! before we can query its size.
    end subroutine gl_realize_callback

    ! Map callback - window has been placed on screen by window manager
    subroutine gl_map_callback(gl_area, user_data) bind(c)
        type(c_ptr), value :: gl_area, user_data

        print '(A)', "DEBUG: Map callback - window placed by WM"

        mapped = .true.

        ! If we have pending dimensions from a resize event, initialize now
        if (.not. initialized .and. pending_width > 0 .and. pending_height > 0) then
            print '(A,I0,A,I0)', "DEBUG: Initializing with pending size: ", pending_width, "x", pending_height
            call init_terminal(pending_width, pending_height)
        end if
    end subroutine gl_map_callback

    ! Query which monitor a widget is on and get its scale factor
    subroutine query_monitor_scale_factor(widget, scale_factor)
        type(c_ptr), intent(in) :: widget
        integer(c_int), intent(out) :: scale_factor
        type(c_ptr) :: native, surface, display, monitor, monitors
        integer(c_int) :: i, n_monitors, mon_scale, max_scale, surface_scale
        logical :: has_hidpi

        ! Default to scale factor 1
        scale_factor = 1
        max_scale = 1
        has_hidpi = .false.

        display = gtk_widget_get_display(widget)
        if (.not. c_associated(display)) then
            print '(A)', "DEBUG: Could not get display from widget"
            return
        end if

        ! List ALL monitors and find maximum scale factor
        monitors = gdk_display_get_monitors(display)
        if (c_associated(monitors)) then
            n_monitors = g_list_model_get_n_items(monitors)
            print '(A,I0,A)', "DEBUG: System has ", n_monitors, " monitors:"
            do i = 0, n_monitors - 1
                monitor = g_list_model_get_item(monitors, i)
                if (c_associated(monitor)) then
                    mon_scale = gdk_monitor_get_scale_factor(monitor)
                    print '(A,I0,A,I0)', "DEBUG:   Monitor ", i, " scale factor: ", mon_scale
                    if (mon_scale > max_scale) max_scale = mon_scale
                    if (mon_scale > 1) has_hidpi = .true.
                    call g_object_unref(monitor)
                end if
            end do
        end if

        ! Query which monitor this widget is actually on (standard GTK4 approach)
        native = gtk_widget_get_native(widget)
        if (.not. c_associated(native)) then
            print '(A)', "DEBUG: Could not get native from widget"
            return
        end if

        surface = gtk_native_get_surface(native)
        if (.not. c_associated(surface)) then
            print '(A)', "DEBUG: Could not get surface from native"
            return
        end if

        monitor = gdk_display_get_monitor_at_surface(display, surface)
        if (.not. c_associated(monitor)) then
            print '(A)', "DEBUG: Could not get monitor from surface"
            return
        end if

        surface_scale = gdk_monitor_get_scale_factor(monitor)
        print '(A,I0)', "DEBUG: Surface monitor query returned scale factor: ", surface_scale

        ! macOS GTK4 workaround: gdk_display_get_monitor_at_surface() returns wrong monitor
        ! If we have HiDPI monitors and surface query returns scale 1, use max scale
        if (has_hidpi .and. surface_scale == 1 .and. max_scale > 1) then
            scale_factor = max_scale
            print '(A,I0,A)', "DEBUG: Applying macOS workaround: using max scale factor ", &
                max_scale, " (GTK surface→monitor mapping is broken)"
        else
            scale_factor = surface_scale
        end if
    end subroutine query_monitor_scale_factor

    ! Initialize terminal (called from resize callback when we have a valid size)
    subroutine init_terminal(width, height)
        integer, intent(in) :: width, height
        character(len=256) :: font_path
        logical :: pty_success
        integer :: grid_rows, grid_cols
        integer(c_int) :: scale_factor
        integer :: physical_width, physical_height

        print '(A,I0,A,I0)', "DEBUG: Initializing terminal with logical size: ", width, "x", height

        ! Query monitor scale factor NOW (gives WM time to finish positioning)
        call query_monitor_scale_factor(global_gl_area, scale_factor)
        print '(A,I0)', "DEBUG: Using scale factor from monitor query: ", scale_factor

        ! GTK GLArea on macOS automatically creates HiDPI-scaled framebuffer
        ! Use LOGICAL dimensions for grid/PTY, but renderer gets physical dims
        physical_width = width * scale_factor
        physical_height = height * scale_factor

        print '(A,I0,A,I0)', "DEBUG: Logical size: ", width, "x", height
        print '(A,I0,A,I0)', "DEBUG: Physical pixel size: ", physical_width, "x", physical_height

        ! Make GL context current (needed for renderer init)
        call gtk_gl_area_make_current(global_gl_area)

        ! Initialize VT parser
        call global_parser%reset()

        ! Find a system font (monospace)
        call find_system_font(font_path)

        ! Initialize renderer with LOGICAL dimensions (GTK handles HiDPI scaling)
        print '(A)', "DEBUG: Using LOGICAL size for renderer (GTK auto-scales framebuffer)"
        if (.not. global_renderer%init(trim(font_path), 16, width, height)) then
            print *, "Error: Failed to initialize renderer"
            return
        end if

        ! Calculate terminal grid size from window and cell dimensions
        grid_cols = physical_width / global_renderer%cell_width
        grid_rows = physical_height / global_renderer%cell_height

        print '(A,I0,A,I0,A,I0,A,I0)', "DEBUG: Physical size ", physical_width, "x", physical_height, &
            ", cells ", global_renderer%cell_width, "x", global_renderer%cell_height, &
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
    end subroutine init_terminal

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

    ! GL resize callback - handle window size changes (including DPI changes from monitor switches)
    subroutine gl_resize_callback(gl_area, width, height, user_data) bind(c)
        type(c_ptr), value :: gl_area, user_data
        integer(c_int), value :: width, height
        integer :: new_grid_cols, new_grid_rows
        integer :: old_cols, old_rows
        integer :: old_cell_width, old_cell_height
        real :: size_ratio
        integer(c_int) :: scale_factor, allocated_width, allocated_height
        integer :: physical_width, physical_height

        if (width <= 0 .or. height <= 0) return

        ! Get both reported size and allocated size for debugging
        allocated_width = gtk_widget_get_allocated_width(global_gl_area)
        allocated_height = gtk_widget_get_allocated_height(global_gl_area)

        ! Use monitor query instead of gtk_widget_get_scale_factor (which returns wrong value on macOS)
        call query_monitor_scale_factor(global_gl_area, scale_factor)

        print '(A,I0,A,I0,A,I0,A,I0,A,I0,A,L1)', "DEBUG: GLArea resize event: reported=", width, "x", height, &
            " allocated=", allocated_width, "x", allocated_height, " scale=", scale_factor, " mapped=", mapped

        ! Store size but wait for map event before initializing
        ! This ensures the window manager has finished placing the window
        if (.not. initialized) then
            pending_width = width
            pending_height = height

            if (mapped) then
                print '(A)', "DEBUG: Window mapped - initializing terminal now..."
                call init_terminal(pending_width, pending_height)
            else
                print '(A)', "DEBUG: Deferring init until window is mapped (tiling WM may move window)..."
            end if
            return
        end if

        ! Get scale factor and calculate physical dimensions
        ! Use monitor query instead of gtk_widget_get_scale_factor (which returns wrong value on macOS)
        call query_monitor_scale_factor(global_gl_area, scale_factor)
        physical_width = width * scale_factor
        physical_height = height * scale_factor

        print '(A,I0,A,I0,A,I0)', "DEBUG: Logical: ", width, "x", height, " Scale: ", scale_factor
        print '(A,I0,A,I0)', "DEBUG: Physical: ", physical_width, "x", physical_height

        ! Save old dimensions
        old_cols = global_grid%cols
        old_rows = global_grid%rows
        old_cell_width = global_renderer%cell_width
        old_cell_height = global_renderer%cell_height

        ! Check if this is a size change (comparing against logical size in renderer)
        size_ratio = real(width) / real(global_renderer%window_width)

        print '(A,F6.3)', "DEBUG: Logical size ratio: ", size_ratio

        ! If significant size change, update renderer viewport with LOGICAL dimensions
        ! (GTK GLArea automatically scales the framebuffer for HiDPI)
        if (abs(size_ratio - 1.0) > 0.05) then
            call global_renderer%resize(width, height)
            print '(A,I0,A,I0)', "DEBUG: Renderer viewport updated to logical: ", width, "x", height
        end if

        ! Calculate grid dimensions from physical size
        new_grid_cols = physical_width / global_renderer%cell_width
        new_grid_rows = physical_height / global_renderer%cell_height

        ! Ensure minimum grid size
        if (new_grid_cols < 10) new_grid_cols = 10
        if (new_grid_rows < 5) new_grid_rows = 5

        print '(A,I0,A,I0,A,I0,A,I0)', "DEBUG: Grid resize: ", &
            old_cols, "x", old_rows, " -> ", new_grid_cols, "x", new_grid_rows

        ! Only resize if dimensions changed
        if (new_grid_cols /= old_cols .or. new_grid_rows /= old_rows) then
            ! Resize the grid (preserves content)
            call global_grid%resize(new_grid_rows, new_grid_cols)

            ! Update PTY window size (sends SIGWINCH to shell)
            call global_pty%resize(new_grid_rows, new_grid_cols)

            ! Update renderer viewport (if not already done above)
            if (abs(size_ratio - 1.0) <= 0.1) then
                call global_renderer%resize(width, height)
            end if

            print '(A)', "DEBUG: Resize complete"
        end if
    end subroutine gl_resize_callback

    ! Key pressed callback - send input to PTY
    function key_pressed_callback(controller, keyval, keycode, state, user_data) &
            bind(c) result(handled)
        type(c_ptr), value :: controller, user_data
        integer(c_int), value :: keyval, keycode, state
        integer(c_int) :: handled
        character(len=16) :: key_string
        integer :: bytes_written, key_len
        integer, parameter :: GDK_CONTROL_MASK = 4  ! Ctrl modifier
        integer, parameter :: GDK_SHIFT_MASK = 1    ! Shift modifier

        handled = 0  ! FALSE by default

        if (.not. initialized) return

        ! Handle scrollback navigation with Shift modifier
        if (iand(state, GDK_SHIFT_MASK) /= 0) then
            if (keyval == 65365) then  ! Shift+Page_Up
                call global_grid%scroll_back(global_grid%rows)
                call gtk_gl_area_queue_render(global_gl_area)
                handled = 1
                return
            else if (keyval == 65366) then  ! Shift+Page_Down
                call global_grid%scroll_forward(global_grid%rows)
                call gtk_gl_area_queue_render(global_gl_area)
                handled = 1
                return
            else if (keyval == 65360) then  ! Shift+Home
                call global_grid%scroll_to_top()
                call gtk_gl_area_queue_render(global_gl_area)
                handled = 1
                return
            else if (keyval == 65367) then  ! Shift+End
                call global_grid%scroll_to_bottom()
                call gtk_gl_area_queue_render(global_gl_area)
                handled = 1
                return
            end if
        end if

        ! Check for Ctrl+Shift+C (copy selection to clipboard)
        if (iand(state, GDK_CONTROL_MASK) /= 0 .and. iand(state, GDK_SHIFT_MASK) /= 0) then
            if (keyval == ichar('C') .or. keyval == ichar('c')) then
                call copy_selection_to_clipboard()
                handled = 1
                return
            end if
        end if

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

            ! Update window title if changed
            if (global_parser%window_title /= last_window_title .and. c_associated(global_window)) then
                call gtk_window_set_title(global_window, trim(global_parser%window_title) // c_null_char)
                last_window_title = global_parser%window_title
            end if

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

    ! Scale factor check callback - detects monitor changes after window auto-snap
    ! Scale factor changed signal handler - called when window moves between monitors with different DPI
    ! This is the proper GTK way to handle DPI changes (used by VTE/GNOME Terminal)
    subroutine scale_factor_changed_callback(object, pspec, user_data) bind(c)
        type(c_ptr), value :: object, pspec, user_data
        integer(c_int) :: new_scale_factor
        integer :: new_physical_width, new_physical_height
        integer :: new_grid_cols, new_grid_rows
        integer :: logical_width, logical_height

        if (.not. initialized) return

        ! Get new scale factor
        new_scale_factor = gtk_widget_get_scale_factor(global_gl_area)

        print '(A,I0)', "DEBUG: Scale factor changed signal - new scale: ", new_scale_factor

        ! Get current logical size
        logical_width = gtk_widget_get_allocated_width(global_gl_area)
        logical_height = gtk_widget_get_allocated_height(global_gl_area)

        ! Calculate new physical dimensions
        new_physical_width = logical_width * new_scale_factor
        new_physical_height = logical_height * new_scale_factor

        print '(A,I0,A,I0,A,I0)', "DEBUG: Logical: ", logical_width, "x", logical_height, &
            " Scale:", new_scale_factor
        print '(A,I0,A,I0)', "DEBUG: New physical size: ", new_physical_width, "x", new_physical_height

        ! Update renderer with new physical dimensions
        call global_renderer%resize(new_physical_width, new_physical_height)

        ! Calculate new grid dimensions
        new_grid_cols = new_physical_width / global_renderer%cell_width
        new_grid_rows = new_physical_height / global_renderer%cell_height

        print '(A,I0,A,I0)', "DEBUG: New grid size: ", new_grid_cols, "x", new_grid_rows

        ! Resize the grid (preserves content)
        call global_grid%resize(new_grid_rows, new_grid_cols)

        ! Update PTY window size (sends SIGWINCH to shell which will redraw)
        call global_pty%resize(new_grid_rows, new_grid_cols)

        ! Request redraw
        call gtk_gl_area_queue_render(global_gl_area)

        print '(A)', "DEBUG: Scale factor change handling complete"
    end subroutine scale_factor_changed_callback

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

    ! Set global window pointer for title updates
    subroutine set_window(window)
        type(c_ptr), intent(in) :: window
        global_window = window
    end subroutine set_window

    ! Mouse button pressed callback
    subroutine mouse_button_pressed_callback(gesture, n_press, x, y, user_data) bind(c)
        type(c_ptr), value :: gesture, user_data
        integer(c_int), value :: n_press
        real(c_double), value :: x, y
        integer :: button, grid_col, grid_row, bytes_written
        character(len=32) :: mouse_seq
        integer :: seq_len
        logical :: mouse_tracking_enabled

        if (.not. initialized) return

        ! Convert pixel coordinates to grid coordinates
        grid_col = int(x / real(global_renderer%cell_width)) + 1
        grid_row = int(y / real(global_renderer%cell_height)) + 1

        ! Clamp to grid bounds
        if (grid_col < 1) grid_col = 1
        if (grid_col > global_grid%cols) grid_col = global_grid%cols
        if (grid_row < 1) grid_row = 1
        if (grid_row > global_grid%rows) grid_row = global_grid%rows

        ! Check if any mouse tracking mode is enabled
        mouse_tracking_enabled = (global_parser%mouse_tracking_x10 .or. &
                                  global_parser%mouse_tracking_vt200 .or. &
                                  global_parser%mouse_tracking_btn .or. &
                                  global_parser%mouse_tracking_any)

        if (mouse_tracking_enabled) then
            ! Mouse tracking is active - send to PTY for vim/etc
            button = 0  ! Default to left button

            ! Generate mouse report based on active mode
            if (global_parser%mouse_tracking_sgr) then
                ! SGR extended mode: ESC [ < Cb ; Cx ; Cy M
                write(mouse_seq, '(A,I0,A,I0,A,I0,A)') char(27)//'[<', button, ';', grid_col, ';', grid_row, 'M'
                seq_len = len_trim(mouse_seq)
            else
                ! X10/VT200 mode: ESC [ M Cb Cx Cy
                mouse_seq(1:3) = char(27)//'[M'
                mouse_seq(4:4) = char(button + 32)
                mouse_seq(5:5) = char(grid_col + 32)
                mouse_seq(6:6) = char(grid_row + 32)
                seq_len = 6
            end if

            ! Send to PTY
            bytes_written = global_pty%write(mouse_seq, seq_len)
        else
            ! Mouse tracking disabled - use for text selection
            mouse_button_pressed = .true.
            call global_grid%set_selection_start(grid_row, grid_col)
            call gtk_gl_area_queue_render(global_gl_area)
        end if
    end subroutine mouse_button_pressed_callback

    ! Mouse button released callback
    subroutine mouse_button_released_callback(gesture, n_press, x, y, user_data) bind(c)
        type(c_ptr), value :: gesture, user_data
        integer(c_int), value :: n_press
        real(c_double), value :: x, y

        if (.not. initialized) return

        mouse_button_pressed = .false.
    end subroutine mouse_button_released_callback

    ! Mouse motion callback
    subroutine mouse_motion_callback(controller, x, y, user_data) bind(c)
        type(c_ptr), value :: controller, user_data
        real(c_double), value :: x, y
        integer :: grid_col, grid_row, bytes_written
        character(len=32) :: mouse_seq
        integer :: seq_len

        if (.not. initialized) return

        ! Convert pixel coordinates to grid coordinates
        grid_col = int(x / real(global_renderer%cell_width)) + 1
        grid_row = int(y / real(global_renderer%cell_height)) + 1

        ! Clamp to grid bounds
        if (grid_col < 1) grid_col = 1
        if (grid_col > global_grid%cols) grid_col = global_grid%cols
        if (grid_row < 1) grid_row = 1
        if (grid_row > global_grid%rows) grid_row = global_grid%rows

        ! Check if we're dragging for selection
        if (mouse_button_pressed .and. .not. global_parser%mouse_tracking_any) then
            ! Update selection end position
            call global_grid%set_selection_end(grid_row, grid_col)
            call gtk_gl_area_queue_render(global_gl_area)
            return
        end if

        ! Report motion if "any event" tracking is enabled
        if (.not. global_parser%mouse_tracking_any) return

        ! Generate mouse motion report
        if (global_parser%mouse_tracking_sgr) then
            ! SGR extended mode: ESC [ < Cb ; Cx ; Cy M (button 3 = motion)
            write(mouse_seq, '(A,I0,A,I0,A,I0,A)') char(27)//'[<', 3, ';', grid_col, ';', grid_row, 'M'
            seq_len = len_trim(mouse_seq)
        else
            ! X10/VT200 mode: ESC [ M Cb Cx Cy (button 35 = motion)
            mouse_seq(1:3) = char(27)//'[M'
            mouse_seq(4:4) = char(35)  ! 3 + 32 for motion
            mouse_seq(5:5) = char(grid_col + 32)
            mouse_seq(6:6) = char(grid_row + 32)
            seq_len = 6
        end if

        ! Send to PTY
        bytes_written = global_pty%write(mouse_seq, seq_len)
    end subroutine mouse_motion_callback

    ! Copy selected text to clipboard
    subroutine copy_selection_to_clipboard()
        character(len=8192) :: selected_text
        integer :: text_len
        type(c_ptr) :: display, clipboard

        if (.not. initialized) return
        if (.not. global_grid%selection_active) return

        ! Get selected text from grid
        call global_grid%get_selected_text(selected_text, text_len)

        if (text_len <= 0) return

        ! Get display and clipboard
        display = gtk_widget_get_display(global_gl_area)
        if (.not. c_associated(display)) return

        clipboard = gdk_display_get_clipboard(display)
        if (.not. c_associated(clipboard)) return

        ! Copy text to clipboard
        call gdk_clipboard_set_text(clipboard, trim(selected_text(1:text_len)) // c_null_char)

        ! Clear selection after copy (standard terminal behavior)
        call global_grid%clear_selection()
        call gtk_gl_area_queue_render(global_gl_area)
    end subroutine copy_selection_to_clipboard

end module fortty_app
