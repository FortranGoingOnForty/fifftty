! Simple unit testing framework for fortty
! Provides assertion helpers and test tracking
module test_framework
    implicit none
    private

    ! Test statistics
    integer, save :: tests_run = 0
    integer, save :: tests_passed = 0
    integer, save :: tests_failed = 0

    public :: assert_equal_int, assert_equal_char, assert_true, assert_false
    public :: test_summary, reset_test_stats, test_begin, test_end

contains

    ! Reset test statistics
    subroutine reset_test_stats()
        tests_run = 0
        tests_passed = 0
        tests_failed = 0
    end subroutine reset_test_stats

    ! Print test summary and return exit code
    function test_summary() result(exit_code)
        integer :: exit_code

        print '(/A)', "========================================="
        print '(A,I0)', "Tests run: ", tests_run
        print '(A,I0)', "Tests passed: ", tests_passed
        print '(A,I0)', "Tests failed: ", tests_failed
        print '(A)', "========================================="
        if (tests_failed == 0) then
            print '(A)', "ALL TESTS PASSED"
            exit_code = 0
        else
            print '(A)', "SOME TESTS FAILED"
            exit_code = 1
        end if
    end function test_summary

    ! Mark beginning of a test
    subroutine test_begin(name)
        character(len=*), intent(in) :: name
        tests_run = tests_run + 1
        print '(/A,A)', "Running test: ", name
    end subroutine test_begin

    ! Mark end of a successful test
    subroutine test_end()
        tests_passed = tests_passed + 1
        print '(A)', "  PASSED"
    end subroutine test_end

    ! Assert that two integers are equal
    subroutine assert_equal_int(actual, expected, message)
        integer, intent(in) :: actual, expected
        character(len=*), intent(in) :: message

        if (actual /= expected) then
            print '(A,A)', "  FAILED: ", message
            print '(A,I0)', "    Expected: ", expected
            print '(A,I0)', "    Actual:   ", actual
            tests_failed = tests_failed + 1
            error stop
        end if
    end subroutine assert_equal_int

    ! Assert that two characters are equal
    subroutine assert_equal_char(actual, expected, message)
        character(len=*), intent(in) :: actual, expected
        character(len=*), intent(in) :: message

        if (actual /= expected) then
            print '(A,A)', "  FAILED: ", message
            print '(A,A)', "    Expected: '", trim(expected), "'"
            print '(A,A)', "    Actual:   '", trim(actual), "'"
            tests_failed = tests_failed + 1
            error stop
        end if
    end subroutine assert_equal_char

    ! Assert that a condition is true
    subroutine assert_true(condition, message)
        logical, intent(in) :: condition
        character(len=*), intent(in) :: message

        if (.not. condition) then
            print '(A,A)', "  FAILED: ", message
            print '(A)', "    Expected: true"
            print '(A)', "    Actual:   false"
            tests_failed = tests_failed + 1
            error stop
        end if
    end subroutine assert_true

    ! Assert that a condition is false
    subroutine assert_false(condition, message)
        logical, intent(in) :: condition
        character(len=*), intent(in) :: message

        if (condition) then
            print '(A,A)', "  FAILED: ", message
            print '(A)', "    Expected: false"
            print '(A)', "    Actual:   true"
            tests_failed = tests_failed + 1
            error stop
        end if
    end subroutine assert_false

end module test_framework
