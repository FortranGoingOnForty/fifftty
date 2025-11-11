module gtk_bindings
    use, intrinsic :: iso_c_binding
    implicit none

    ! GTK4 C API bindings using ISO_C_BINDING
    ! These are minimal bindings for Phase 0: just enough to open a window

    ! Opaque pointer types for GTK objects
    type(c_ptr) :: null_ptr = c_null_ptr

    ! GApplicationFlags enum
    integer(c_int), parameter :: G_APPLICATION_DEFAULT_FLAGS = 0
    integer(c_int), parameter :: G_APPLICATION_FLAGS_NONE = 0

    interface
        ! Application lifecycle
        function gtk_application_new(application_id, flags) bind(c, name='gtk_application_new')
            import :: c_ptr, c_char, c_int
            character(kind=c_char), dimension(*) :: application_id
            integer(c_int), value :: flags
            type(c_ptr) :: gtk_application_new
        end function gtk_application_new

        function g_application_run(application, argc, argv) bind(c, name='g_application_run')
            import :: c_ptr, c_int
            type(c_ptr), value :: application
            integer(c_int), value :: argc
            type(c_ptr), value :: argv
            integer(c_int) :: g_application_run
        end function g_application_run

        subroutine g_object_unref(object) bind(c, name='g_object_unref')
            import :: c_ptr
            type(c_ptr), value :: object
        end subroutine g_object_unref

        ! Window management
        function gtk_application_window_new(application) bind(c, name='gtk_application_window_new')
            import :: c_ptr
            type(c_ptr), value :: application
            type(c_ptr) :: gtk_application_window_new
        end function gtk_application_window_new

        subroutine gtk_window_set_title(window, title) bind(c, name='gtk_window_set_title')
            import :: c_ptr, c_char
            type(c_ptr), value :: window
            character(kind=c_char), dimension(*) :: title
        end subroutine gtk_window_set_title

        subroutine gtk_window_set_default_size(window, width, height) bind(c, name='gtk_window_set_default_size')
            import :: c_ptr, c_int
            type(c_ptr), value :: window
            integer(c_int), value :: width, height
        end subroutine gtk_window_set_default_size

        subroutine gtk_window_present(window) bind(c, name='gtk_window_present')
            import :: c_ptr
            type(c_ptr), value :: window
        end subroutine gtk_window_present

        ! Signal handling
        function g_signal_connect_data(instance, detailed_signal, c_handler, &
                                       data, destroy_data, connect_flags) &
                                       bind(c, name='g_signal_connect_data')
            import :: c_ptr, c_char, c_funptr, c_int, c_long
            type(c_ptr), value :: instance
            character(kind=c_char), dimension(*) :: detailed_signal
            type(c_funptr), value :: c_handler
            type(c_ptr), value :: data
            type(c_funptr), value :: destroy_data
            integer(c_int), value :: connect_flags
            integer(c_long) :: g_signal_connect_data
        end function g_signal_connect_data
    end interface

contains

    ! Helper function to connect signals without all the ceremony
    function g_signal_connect(instance, detailed_signal, c_handler, data) result(handler_id)
        type(c_ptr), intent(in) :: instance
        character(len=*), intent(in) :: detailed_signal
        type(c_funptr), intent(in) :: c_handler
        type(c_ptr), intent(in) :: data
        integer(c_long) :: handler_id

        handler_id = g_signal_connect_data(instance, &
                                           trim(detailed_signal) // c_null_char, &
                                           c_handler, &
                                           data, &
                                           c_null_funptr, &
                                           0_c_int)
    end function g_signal_connect

    ! Helper to convert Fortran string to C string
    function f_c_string(f_string) result(c_string)
        character(len=*), intent(in) :: f_string
        character(len=:, kind=c_char), allocatable :: c_string
        c_string = trim(f_string) // c_null_char
    end function f_c_string

end module gtk_bindings
