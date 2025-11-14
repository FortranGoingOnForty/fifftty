program fortty_main
    use, intrinsic :: iso_c_binding
    use gtk_bindings
    use fortty_app  ! Global state module
    implicit none

    type(c_ptr) :: app
    integer(c_int) :: status
    character(len=100) :: app_id

    ! Application ID
    app_id = "com.fortrangoinonforty.fortty"

    ! Create GTK application
    app = gtk_application_new(f_c_string(app_id), G_APPLICATION_DEFAULT_FLAGS)

    if (.not. c_associated(app)) then
        print *, "Error: Failed to create GTK application"
        stop 1
    end if

    ! Connect the activate signal
    call connect_activate_signal(app)

    ! Run the application
    status = g_application_run(app, 0_c_int, c_null_ptr)

    ! Clean up
    call g_object_unref(app)

    if (status /= 0) then
        print *, "Application exited with status:", status
        stop 1
    end if

contains

    ! Connect activate signal
    subroutine connect_activate_signal(application)
        type(c_ptr), intent(in) :: application
        integer(c_long) :: handler_id
        type(c_funptr) :: callback_ptr

        callback_ptr = c_funloc(activate_callback)
        handler_id = g_signal_connect(application, "activate", callback_ptr, c_null_ptr)

        if (handler_id == 0) then
            print *, "Warning: Failed to connect activate signal"
        end if
    end subroutine connect_activate_signal

    ! Activate callback - main setup
    subroutine activate_callback(app, user_data) bind(c)
        type(c_ptr), value :: app, user_data
        type(c_ptr) :: window, gl_area, key_controller

        ! Create window
        window = gtk_application_window_new(app)
        if (.not. c_associated(window)) then
            print *, "Error: Failed to create window"
            return
        end if

        ! Save window pointer for title updates
        call set_window(window)

        call gtk_window_set_title(window, f_c_string("fortty - Terminal Emulator"))
        call gtk_window_set_default_size(window, 800_c_int, 600_c_int)

        ! Create GLArea widget for OpenGL rendering
        gl_area = gtk_gl_area_new()
        if (.not. c_associated(gl_area)) then
            print *, "Error: Failed to create GLArea"
            return
        end if
        global_gl_area = gl_area

        ! Set size request to ensure GLArea has dimensions
        call gtk_widget_set_size_request(gl_area, 800_c_int, 600_c_int)

        ! Enable auto-rendering - GTK will handle render timing
        call gtk_gl_area_set_auto_render(gl_area, 1_c_int)

        ! Make GLArea focusable so it can receive keyboard events
        call gtk_widget_set_focusable(gl_area, 1_c_int)

        ! Add GLArea to window
        call gtk_window_set_child(window, gl_area)

        ! Connect GLArea signals
        call connect_gl_signals(gl_area)

        ! Set up keyboard input
        key_controller = gtk_event_controller_key_new()
        call gtk_widget_add_controller(gl_area, key_controller)
        call connect_key_signals(key_controller)

        ! Show window
        call gtk_window_present(window)

        ! Give GLArea keyboard focus so it receives key events
        call gtk_widget_grab_focus(gl_area)
    end subroutine activate_callback

    ! Connect GL Area signals
    subroutine connect_gl_signals(gl_area)
        type(c_ptr), intent(in) :: gl_area
        integer(c_long) :: handler_id

        ! Realize signal - called when GL context is created
        handler_id = g_signal_connect(gl_area, "realize", c_funloc(gl_realize_callback), c_null_ptr)

        ! Map signal - called when widget is placed on screen (after WM positioning)
        ! This fires AFTER tiling WMs move windows, ensuring correct scale factor
        handler_id = g_signal_connect(gl_area, "map", c_funloc(gl_map_callback), c_null_ptr)

        ! Render signal - called when widget needs redrawing
        handler_id = g_signal_connect(gl_area, "render", c_funloc(gl_render_callback), c_null_ptr)

        ! Resize signal - called when widget size changes
        handler_id = g_signal_connect(gl_area, "resize", c_funloc(gl_resize_callback), c_null_ptr)

        ! Scale factor signal - called when widget moves between monitors with different DPI
        ! This is the proper GTK way to handle DPI changes (used by VTE/GNOME Terminal)
        handler_id = g_signal_connect(gl_area, "notify::scale-factor", &
                                      c_funloc(scale_factor_changed_callback), c_null_ptr)
    end subroutine connect_gl_signals

    ! Connect keyboard signals
    subroutine connect_key_signals(controller)
        type(c_ptr), intent(in) :: controller
        integer(c_long) :: handler_id

        handler_id = g_signal_connect(controller, "key-pressed", &
                                      c_funloc(key_pressed_callback), c_null_ptr)
    end subroutine connect_key_signals

end program fortty_main
