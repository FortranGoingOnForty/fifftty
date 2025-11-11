module freetype_bindings
    use, intrinsic :: iso_c_binding
    implicit none

    ! FreeType types (mostly opaque pointers)
    type(c_ptr) :: ft_library_null = c_null_ptr
    type(c_ptr) :: ft_face_null = c_null_ptr

    ! FreeType error codes
    integer(c_int), parameter :: FT_Err_Ok = 0

    ! Load flags
    integer(c_int), parameter :: FT_LOAD_RENDER = int(z'04', c_int)
    integer(c_int), parameter :: FT_LOAD_DEFAULT = 0

    ! Render modes
    integer(c_int), parameter :: FT_RENDER_MODE_NORMAL = 0

    ! Glyph metrics structure (partial - only what we need)
    type, bind(c) :: FT_Glyph_Metrics
        integer(c_long) :: width
        integer(c_long) :: height
        integer(c_long) :: horiBearingX
        integer(c_long) :: horiBearingY
        integer(c_long) :: horiAdvance
        integer(c_long) :: vertBearingX
        integer(c_long) :: vertBearingY
        integer(c_long) :: vertAdvance
    end type FT_Glyph_Metrics

    ! Bitmap structure
    type, bind(c) :: FT_Bitmap
        integer(c_int) :: rows
        integer(c_int) :: width
        integer(c_int) :: pitch
        type(c_ptr) :: buffer
        integer(c_short) :: num_grays
        integer(c_char) :: pixel_mode
        integer(c_char) :: palette_mode
        type(c_ptr) :: palette
    end type FT_Bitmap

    ! Glyph slot structure (partial)
    type, bind(c) :: FT_GlyphSlotRec
        type(c_ptr) :: library
        type(c_ptr) :: face
        type(c_ptr) :: next
        integer(c_int) :: reserved
        type(FT_Glyph_Metrics) :: metrics
        integer(c_long) :: linearHoriAdvance
        integer(c_long) :: linearVertAdvance
        integer(c_long) :: advance_x
        integer(c_long) :: advance_y
        integer(c_int) :: format
        type(FT_Bitmap) :: bitmap
        integer(c_int) :: bitmap_left
        integer(c_int) :: bitmap_top
        ! ... more fields exist but we don't need them
    end type FT_GlyphSlotRec

    ! Face structure (partial - we mainly use it as opaque pointer)
    type, bind(c) :: FT_FaceRec
        integer(c_long) :: num_faces
        integer(c_long) :: face_index
        integer(c_long) :: face_flags
        integer(c_long) :: style_flags
        integer(c_long) :: num_glyphs
        type(c_ptr) :: family_name
        type(c_ptr) :: style_name
        integer(c_int) :: num_fixed_sizes
        type(c_ptr) :: available_sizes
        integer(c_int) :: num_charmaps
        type(c_ptr) :: charmaps
        ! ... more fields
        type(c_ptr) :: glyph  ! Points to FT_GlyphSlotRec
        ! ... more fields we don't need
    end type FT_FaceRec

    interface
        ! Library management
        function FT_Init_FreeType(alibrary) bind(c, name='FT_Init_FreeType')
            import :: c_int, c_ptr
            type(c_ptr) :: alibrary
            integer(c_int) :: FT_Init_FreeType
        end function FT_Init_FreeType

        function FT_Done_FreeType(library) bind(c, name='FT_Done_FreeType')
            import :: c_int, c_ptr
            type(c_ptr), value :: library
            integer(c_int) :: FT_Done_FreeType
        end function FT_Done_FreeType

        ! Face management
        function FT_New_Face(library, filepathname, face_index, aface) &
                           bind(c, name='FT_New_Face')
            import :: c_int, c_ptr, c_char, c_long
            type(c_ptr), value :: library
            character(kind=c_char), dimension(*) :: filepathname
            integer(c_long), value :: face_index
            type(c_ptr) :: aface
            integer(c_int) :: FT_New_Face
        end function FT_New_Face

        function FT_Done_Face(face) bind(c, name='FT_Done_Face')
            import :: c_int, c_ptr
            type(c_ptr), value :: face
            integer(c_int) :: FT_Done_Face
        end function FT_Done_Face

        function FT_Set_Pixel_Sizes(face, pixel_width, pixel_height) &
                                   bind(c, name='FT_Set_Pixel_Sizes')
            import :: c_int, c_ptr
            type(c_ptr), value :: face
            integer(c_int), value :: pixel_width, pixel_height
            integer(c_int) :: FT_Set_Pixel_Sizes
        end function FT_Set_Pixel_Sizes

        ! Glyph loading
        function FT_Load_Char(face, char_code, load_flags) bind(c, name='FT_Load_Char')
            import :: c_int, c_ptr, c_long
            type(c_ptr), value :: face
            integer(c_long), value :: char_code
            integer(c_int), value :: load_flags
            integer(c_int) :: FT_Load_Char
        end function FT_Load_Char

        function FT_Render_Glyph(slot, render_mode) bind(c, name='FT_Render_Glyph')
            import :: c_int, c_ptr
            type(c_ptr), value :: slot
            integer(c_int), value :: render_mode
            integer(c_int) :: FT_Render_Glyph
        end function FT_Render_Glyph

        function FT_Get_Char_Index(face, charcode) bind(c, name='FT_Get_Char_Index')
            import :: c_int, c_ptr, c_long
            type(c_ptr), value :: face
            integer(c_long), value :: charcode
            integer(c_int) :: FT_Get_Char_Index
        end function FT_Get_Char_Index

    end interface

contains

    ! Helper to get glyph slot from face
    function ft_face_glyph(face) result(glyph_slot)
        type(c_ptr), intent(in) :: face
        type(c_ptr) :: glyph_slot
        type(FT_FaceRec), pointer :: face_rec

        if (.not. c_associated(face)) then
            glyph_slot = c_null_ptr
            return
        end if

        call c_f_pointer(face, face_rec)
        glyph_slot = face_rec%glyph
    end function ft_face_glyph

end module freetype_bindings
