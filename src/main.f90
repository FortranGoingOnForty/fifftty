program fortty_main
    use, intrinsic :: iso_c_binding
    use gtk_bindings
    implicit none

    type(c_ptr) :: app
    integer(c_int) :: status
    character(len=100) :: app_id

    ! Application ID (reverse domain notation)
    app_id = "com.fortrangoinonforty.fortty"

    ! Create GTK application
    app = gtk_application_new(f_c_string(app_id), G_APPLICATION_DEFAULT_FLAGS)

    if (.not. c_associated(app)) then
        print *, "Error: Failed to create GTK application"
        stop 1
    end if

    ! Connect the activate signal to our callback
    call connect_activate_signal(app)

    ! Run the application
    status = g_application_run(app, 0_c_int, c_null_ptr)

    ! Clean up
    call g_object_unref(app)

    ! Exit with application status
    if (status /= 0) then
        print *, "Application exited with status:", status
        stop 1
    end if

contains

    ! Connect the activate signal
    subroutine connect_activate_signal(application)
        type(c_ptr), intent(in) :: application
        integer(c_long) :: handler_id
        type(c_funptr) :: callback_ptr

        ! Get function pointer to our activate callback
        callback_ptr = c_funloc(activate_callback)

        ! Connect signal
        handler_id = g_signal_connect(application, "activate", callback_ptr, c_null_ptr)

        if (handler_id == 0) then
            print *, "Warning: Failed to connect activate signal"
        end if
    end subroutine connect_activate_signal

    ! Activate callback - called when the application starts
    subroutine activate_callback(app, user_data) bind(c)
        type(c_ptr), value :: app, user_data
        type(c_ptr) :: window

        ! Create application window
        window = gtk_application_window_new(app)

        if (.not. c_associated(window)) then
            print *, "Error: Failed to create window"
            return
        end if

        ! Configure window
        call gtk_window_set_title(window, f_c_string("fortty - Terminal Emulator"))
        call gtk_window_set_default_size(window, 800_c_int, 600_c_int)

        ! Show window
        call gtk_window_present(window)

        print *, "fortty: Window created successfully"
    end subroutine activate_callback

end program fortty_main
