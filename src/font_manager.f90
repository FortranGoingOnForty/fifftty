module font_manager
    use, intrinsic :: iso_c_binding
    use freetype_bindings
    use opengl_bindings
    use gtk_bindings, only: f_c_string
    implicit none
    private

    ! Maximum glyphs in atlas (Phase 1: ASCII only)
    integer, parameter :: MAX_GLYPHS = 128

    ! Glyph information
    type, public :: glyph_info_t
        real(GLfloat) :: tex_x, tex_y          ! Texture coordinates (0-1)
        real(GLfloat) :: tex_width, tex_height ! Texture size (0-1)
        integer :: width, height               ! Pixel dimensions
        integer :: bearing_x, bearing_y        ! Glyph bearing
        integer :: advance                     ! Horizontal advance
        logical :: loaded                      ! Is this glyph loaded?
    end type glyph_info_t

    ! Font manager type
    type, public :: font_mgr_t
        type(c_ptr) :: ft_library = c_null_ptr
        type(c_ptr) :: ft_face = c_null_ptr
        integer(GLuint) :: atlas_texture = 0
        integer :: atlas_width = 0
        integer :: atlas_height = 0
        integer :: font_size = 16
        integer :: line_height = 0      ! Actual line height from font metrics
        integer :: cell_advance = 0     ! Cell width (max advance)
        type(glyph_info_t) :: glyphs(0:MAX_GLYPHS-1)
    contains
        procedure :: init => font_mgr_init
        procedure :: destroy => font_mgr_destroy
        procedure :: get_glyph => font_mgr_get_glyph
    end type font_mgr_t

contains

    ! Initialize font manager and load font
    function font_mgr_init(this, font_path, font_size) result(success)
        class(font_mgr_t), intent(inout) :: this
        character(len=*), intent(in) :: font_path
        integer, intent(in) :: font_size
        logical :: success

        integer(c_int) :: error
        type(c_ptr), target :: library_ptr, face_ptr
        character(len=:, kind=c_char), allocatable, target :: c_font_path

        success = .false.
        this%font_size = font_size

        ! Explicitly initialize pointers
        library_ptr = transfer(0_c_intptr_t, library_ptr)
        face_ptr = transfer(0_c_intptr_t, face_ptr)

        ! Convert font path to C string using helper
        c_font_path = f_c_string(font_path)

        ! Initialize FreeType
        error = FT_Init_FreeType(c_loc(library_ptr))
        if (error /= FT_Err_Ok .or. .not. c_associated(library_ptr)) then
            print *, "Error: Failed to initialize FreeType"
            return
        end if
        this%ft_library = library_ptr

        ! Load font face
        error = FT_New_Face(this%ft_library, c_loc(c_font_path), &
                           0_c_long, c_loc(face_ptr))
        if (error /= FT_Err_Ok) then
            print *, "Error: Failed to load font:", trim(font_path)
            error = FT_Done_FreeType(this%ft_library)
            return
        end if
        this%ft_face = face_ptr

        ! Set pixel size
        error = FT_Set_Pixel_Sizes(this%ft_face, 0_c_int, int(font_size, c_int))
        if (error /= FT_Err_Ok) then
            print *, "Error: Failed to set font size"
            error = FT_Done_Face(this%ft_face)
            error = FT_Done_FreeType(this%ft_library)
            return
        end if

        ! Calculate font metrics from FreeType face
        call calculate_font_metrics(this)

        ! Create glyph atlas
        call create_atlas(this)

        success = .true.
    end function font_mgr_init

    ! Calculate font metrics from FreeType face
    subroutine calculate_font_metrics(this)
        class(font_mgr_t), intent(inout) :: this
        type(FT_FaceRec), pointer :: face_rec
        integer(c_long) :: height_26_6

        call c_f_pointer(this%ft_face, face_rec)

        ! For terminals, line_height = (ascender - descender) in pixels
        ! FreeType stores metrics in 26.6 fixed-point format after FT_Set_Pixel_Sizes
        ! Get the height from the size metrics (already in pixels)
        ! Use glyph slot to get metrics in pixels
        height_26_6 = int(face_rec%height, c_long)

        ! Convert from font units to pixels
        ! height is in font units, scale by (size / units_per_EM)
        this%line_height = int((height_26_6 * int(this%font_size, c_long)) / &
                          int(face_rec%units_per_EM, c_long))

        ! For fixed-width terminals, use max_advance_width
        this%cell_advance = int((int(face_rec%max_advance_width, c_long) * &
                            int(this%font_size, c_long)) / &
                            int(face_rec%units_per_EM, c_long))
    end subroutine calculate_font_metrics

    ! Create texture atlas with all ASCII glyphs
    subroutine create_atlas(this)
        class(font_mgr_t), intent(inout) :: this
        integer :: i, max_height, total_width, current_x, success_count
        integer(c_int) :: error
        type(c_ptr) :: glyph_slot
        type(FT_GlyphSlotRec), pointer :: glyph
        type(FT_Bitmap), pointer :: bitmap
        integer(c_signed_char), pointer :: bitmap_data(:)
        integer, allocatable :: atlas_buffer(:,:)

        ! First pass: find atlas dimensions
        max_height = 0
        total_width = 0
        success_count = 0

        do i = 32, 126  ! Printable ASCII
            error = FT_Load_Char(this%ft_face, int(i, c_long), FT_LOAD_RENDER)
            if (error /= FT_Err_Ok) cycle

            glyph_slot = ft_face_glyph(this%ft_face)
            if (.not. c_associated(glyph_slot)) cycle

            call c_f_pointer(glyph_slot, glyph)
            total_width = total_width + glyph%bitmap%width + 1  ! +1 for padding
            if (glyph%bitmap%rows > max_height) max_height = glyph%bitmap%rows

            ! For monospace terminal, ensure cell_advance is at least as wide as widest glyph
            if (glyph%bitmap%width > this%cell_advance) then
                this%cell_advance = glyph%bitmap%width
            end if

            success_count = success_count + 1
        end do

        ! Add some padding
        max_height = max_height + 2
        total_width = total_width + 2

        ! Allocate atlas buffer (initialize to zero)
        allocate(atlas_buffer(total_width, max_height))
        atlas_buffer = 0

        ! Second pass: copy glyphs into atlas
        current_x = 1
        do i = 32, 126
            error = FT_Load_Char(this%ft_face, int(i, c_long), FT_LOAD_RENDER)
            if (error /= FT_Err_Ok) then
                this%glyphs(i)%loaded = .false.
                cycle
            end if

            glyph_slot = ft_face_glyph(this%ft_face)
            if (.not. c_associated(glyph_slot)) then
                this%glyphs(i)%loaded = .false.
                cycle
            end if

            call c_f_pointer(glyph_slot, glyph)
            bitmap => glyph%bitmap

            ! Store glyph info
            this%glyphs(i)%width = bitmap%width
            this%glyphs(i)%height = bitmap%rows
            this%glyphs(i)%bearing_x = glyph%bitmap_left
            this%glyphs(i)%bearing_y = glyph%bitmap_top
            this%glyphs(i)%advance = int(glyph%advance%x / 64)  ! Convert from 26.6 fixed point

            ! Texture coordinates (normalized to 0-1)
            this%glyphs(i)%tex_x = real(current_x, GLfloat) / real(total_width, GLfloat)
            this%glyphs(i)%tex_y = 0.0
            this%glyphs(i)%tex_width = real(bitmap%width, GLfloat) / real(total_width, GLfloat)
            this%glyphs(i)%tex_height = real(bitmap%rows, GLfloat) / real(max_height, GLfloat)
            this%glyphs(i)%loaded = .true.

            ! Copy bitmap data into atlas
            if (c_associated(bitmap%buffer) .and. bitmap%width > 0 .and. bitmap%rows > 0) then
                call c_f_pointer(bitmap%buffer, bitmap_data, [bitmap%width * bitmap%rows])
                call copy_glyph_to_atlas(atlas_buffer, bitmap_data, current_x, 1, &
                                        bitmap%width, bitmap%rows, total_width, max_height)
            end if

            current_x = current_x + bitmap%width + 1
        end do

        ! Create OpenGL texture from atlas
        call create_texture(this, atlas_buffer, total_width, max_height)

        deallocate(atlas_buffer)
    end subroutine create_atlas

    ! Copy glyph bitmap to atlas buffer
    subroutine copy_glyph_to_atlas(atlas, glyph_data, x, y, width, height, atlas_width, atlas_height)
        integer, intent(inout) :: atlas(:,:)
        integer(c_signed_char), intent(in) :: glyph_data(:)
        integer, intent(in) :: x, y, width, height, atlas_width, atlas_height
        integer :: row, col, glyph_idx

        do row = 1, height
            do col = 1, width
                if (x + col - 1 <= atlas_width .and. y + row - 1 <= atlas_height) then
                    glyph_idx = (row - 1) * width + col
                    ! Convert signed char to unsigned value (0-255)
                    atlas(x + col - 1, y + row - 1) = iand(int(glyph_data(glyph_idx)), 255)
                end if
            end do
        end do
    end subroutine copy_glyph_to_atlas

    ! Create OpenGL texture from atlas buffer
    subroutine create_texture(this, atlas, width, height)
        class(font_mgr_t), intent(inout) :: this
        integer, intent(in) :: atlas(:,:)
        integer, intent(in) :: width, height
        integer(GLuint), target :: texture
        integer(c_int8_t), allocatable, target :: gl_buffer(:)
        integer :: i, j, val

        this%atlas_width = width
        this%atlas_height = height

        ! Convert atlas to OpenGL buffer format (row-major for glTexImage2D)
        allocate(gl_buffer(width * height))
        do j = 1, height
            do i = 1, width
                val = atlas(i, j)
                ! Ensure value is in 0-255 range as unsigned byte
                if (val < 0) val = 0
                if (val > 255) val = 255
                gl_buffer((j-1) * width + i) = int(val, c_int8_t)
            end do
        end do

        ! Create texture
        call glGenTextures(1, c_loc(texture))
        this%atlas_texture = texture

        call glBindTexture(GL_TEXTURE_2D, texture)

        ! Set texture parameters
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        call glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

        ! Set pixel unpacking alignment
        call glPixelStorei(GL_UNPACK_ALIGNMENT, 1)

        ! Upload texture data (GL treats c_int8_t as unsigned byte when we specify GL_UNSIGNED_BYTE)
        call glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, width, height, 0, &
                         GL_RED, GL_UNSIGNED_BYTE, c_loc(gl_buffer))

        call glBindTexture(GL_TEXTURE_2D, 0)

        deallocate(gl_buffer)
    end subroutine create_texture

    ! Get glyph info
    function font_mgr_get_glyph(this, codepoint) result(glyph)
        class(font_mgr_t), intent(in) :: this
        integer, intent(in) :: codepoint
        type(glyph_info_t) :: glyph

        ! For Phase 1, only support ASCII
        if (codepoint >= 0 .and. codepoint < MAX_GLYPHS) then
            glyph = this%glyphs(codepoint)
        else
            ! Return space as fallback
            glyph = this%glyphs(32)
        end if
    end function font_mgr_get_glyph

    ! Destroy font manager
    subroutine font_mgr_destroy(this)
        class(font_mgr_t), intent(inout) :: this
        integer(c_int) :: error

        if (c_associated(this%ft_face)) then
            error = FT_Done_Face(this%ft_face)
            this%ft_face = c_null_ptr
        end if

        if (c_associated(this%ft_library)) then
            error = FT_Done_FreeType(this%ft_library)
            this%ft_library = c_null_ptr
        end if
    end subroutine font_mgr_destroy

end module font_manager
