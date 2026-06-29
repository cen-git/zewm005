*&---------------------------------------------------------------------*
*& Class:        ZCL_ZEWM005_TRANSFER
*& Description:  Internal Transfer (EWM -> IM) - Backend Logic
*& Reference:    zewm006 pattern (ZZAPI_UI_ODATA OData V2 dispatch)
*&---------------------------------------------------------------------*
CLASS zcl_zewm005_transfer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Called from OData service handler (similar to ZZAPI_UI_ODATA pattern)
    " iv_code    : transaction code (e.g. 'ZEWM005-CHECK-DEST')
    " iv_reqparam: JSON string with { fname, mname, ...params }
    " ev_restype : result type (S=success, E=error, W=warning)
    " ev_resmsg  : result message
    " ev_resdata : result data (JSON)
    CLASS-METHODS process
      IMPORTING
        iv_code         TYPE string
        iv_reqparam     TYPE string
      EXPORTING
        ev_restype      TYPE char1
        ev_resmsg       TYPE string
        ev_resdata      TYPE string.

  PRIVATE SECTION.
    " Method dispatcher
    METHODS dispatch
      IMPORTING
        iv_mname        TYPE string
        iv_params       TYPE string
      EXPORTING
        ev_restype      TYPE char1
        ev_resmsg       TYPE string
        ev_resdata      TYPE string.

    " ── CHECK_DEST: Validate destination storage location ──
    METHODS check_dest
      IMPORTING
        iv_destloc      TYPE char4
      EXPORTING
        ev_restype      TYPE char1
        ev_resmsg       TYPE string.

    " ── CHECK_HU: Validate handling unit ──
    METHODS check_hu
      IMPORTING
        iv_hu           TYPE char10
      EXPORTING
        ev_restype      TYPE char1
        ev_resmsg       TYPE string.

    " ── CONFIRM: Execute transfer ──
    METHODS confirm
      IMPORTING
        iv_destloc      TYPE char4
        it_hus          TYPE string_table
      EXPORTING
        ev_restype      TYPE char1
        ev_resmsg       TYPE string.

    " ── Helper: check if HU is highest-level ──
    METHODS is_highest_level_hu
      IMPORTING
        iv_hu           TYPE char10
      RETURNING
        VALUE(rv_yes)   TYPE abap_bool.

    " ── Helper: check if HU exists in EWM stock ──
    METHODS hu_exists_in_ewm
      IMPORTING
        iv_hu           TYPE char10
      RETURNING
        VALUE(rv_yes)   TYPE abap_bool.

    " ── Helper: check if HU exists in handling unit master ──
    METHODS hu_exists_in_master
      IMPORTING
        iv_hu           TYPE char10
      RETURNING
        VALUE(rv_yes)   TYPE abap_bool.

ENDCLASS.


CLASS zcl_zewm005_transfer IMPLEMENTATION.

  " ── Main entry point (called by OData service handler) ───────────────
  METHOD process.
    DATA:
      lv_mname  TYPE string,
      lo_obj    TYPE REF TO zcl_zewm005_transfer.

    TRY.
        " Extract mname from reqparam JSON
        lv_mname = /ui2/cl_json=>get_value( json = iv_reqparam path = '/mname' ).
        IF lv_mname IS INITIAL.
          ev_restype = 'E'.
          ev_resmsg  = 'Missing method name (mname) in request.'.
          RETURN.
        ENDIF.

        " Create instance and dispatch
        CREATE OBJECT lo_obj.
        lo_obj->dispatch(
          EXPORTING
            iv_mname    = lv_mname
            iv_params   = iv_reqparam
          IMPORTING
            ev_restype  = ev_restype
            ev_resmsg   = ev_resmsg
            ev_resdata  = ev_resdata
        ).

      CATCH cx_root INTO DATA(lx_error).
        ev_restype = 'E'.
        ev_resmsg  = lx_error->get_text( ).
    ENDTRY.
  ENDMETHOD.


  " ── Method dispatcher ────────────────────────────────────────────────
  METHOD dispatch.
    DATA: lv_destloc TYPE char4,
          lv_hu      TYPE char10,
          lt_hus     TYPE string_table,
          lv_hus_str TYPE string.

    CASE iv_mname.
      WHEN 'CHECK_DEST'.
        lv_destloc = /ui2/cl_json=>get_value( json = iv_params path = '/destLoc' ).
        me->check_dest(
          EXPORTING iv_destloc = lv_destloc
          IMPORTING ev_restype = ev_restype
                    ev_resmsg  = ev_resmsg
        ).

      WHEN 'CHECK_HU'.
        lv_hu = /ui2/cl_json=>get_value( json = iv_params path = '/hu' ).
        me->check_hu(
          EXPORTING iv_hu      = lv_hu
          IMPORTING ev_restype = ev_restype
                    ev_resmsg  = ev_resmsg
        ).

      WHEN 'CONFIRM'.
        lv_destloc = /ui2/cl_json=>get_value( json = iv_params path = '/destLoc' ).
        " Parse HU array from JSON
        lv_hus_str = /ui2/cl_json=>get_value( json = iv_params path = '/hus' ).
        IF lv_hus_str IS NOT INITIAL.
          /ui2/cl_json=>deserialize(
            EXPORTING json = lv_hus_str
            CHANGING  data = lt_hus
          ).
        ENDIF.
        me->confirm(
          EXPORTING iv_destloc = lv_destloc
                    it_hus     = lt_hus
          IMPORTING ev_restype = ev_restype
                    ev_resmsg  = ev_resmsg
        ).

      WHEN OTHERS.
        ev_restype = 'E'.
        ev_resmsg  = |Unknown method: { iv_mname }|.
    ENDCASE.
  ENDMETHOD.


  " ── CHECK_DEST ──────────────────────────────────────────────────────
  " Validates against I_StorageLocation
  " Business rules:
  "   1. Storage location must exist in I_StorageLocation
  "   2. Storage location 'A002' is not allowed
  METHOD check_dest.
    DATA: lv_storage_location TYPE char4.

    " Field is mandatory (should be caught by frontend, but double-check)
    IF iv_destloc IS INITIAL.
      ev_restype = 'E'.
      ev_resmsg  = |Field 'Destination Location' is mandatory.|.
      RETURN.
    ENDIF.

    " Rule: A002 is not allowed
    IF iv_destloc = 'A002'.
      ev_restype = 'E'.
      ev_resmsg  = |Storage Location { iv_destloc } is not allowed.|.
      RETURN.
    ENDIF.

    " Rule: Storage location must exist
    SELECT SINGLE storagelocation
      FROM i_storagelocation
      INTO lv_storage_location
      WHERE storagelocation = iv_destloc.

    IF sy-subrc <> 0.
      ev_restype = 'E'.
      ev_resmsg  = |Storage Location { iv_destloc } doesn't exist.|.
      RETURN.
    ENDIF.

    " Valid
    ev_restype = 'S'.
    ev_resmsg  = ''.
  ENDMETHOD.


  " ── CHECK_HU ────────────────────────────────────────────────────────
  " Validates against I_EWM_AvailableStock and I_HANDLINGUNITTP
  " Business rules:
  "   1. HU must exist in I_EWM_AvailableStock (HandlingUnitNumber)
  "   2. If HU found in I_HANDLINGUNITTP but parent HU is not null,
  "      user must scan the highest-level HU instead
  "   3. If HU not in EWM stock but found in master, it doesn't exist as available
  METHOD check_hu.
    DATA: lv_ewm_hu  TYPE char10,
          lv_master_hu TYPE char10,
          lv_parent_hu TYPE char10.

    IF iv_hu IS INITIAL.
      ev_restype = 'S'.  " empty is OK (user may tab past)
      RETURN.
    ENDIF.

    " Step 1: Check I_EWM_AvailableStock
    SELECT SINGLE handlingunitnumber
      FROM i_ewm_availablestock
      INTO lv_ewm_hu
      WHERE handlingunitnumber = iv_hu.

    IF sy-subrc = 0.
      " HU exists in EWM stock - it's valid
      ev_restype = 'S'.
      RETURN.
    ENDIF.

    " Step 2: Not found in EWM stock - check if it exists in master data
    SELECT SINGLE handlingunitexternalid, parenthandlingnumber
      FROM i_handlingunittptp
      INTO (lv_master_hu, lv_parent_hu)
      WHERE handlingunitexternalid = iv_hu.

    IF sy-subrc = 0.
      " Found in master data
      IF lv_parent_hu IS NOT INITIAL.
        " Has parent HU → user must scan the highest-level HU
        ev_restype = 'E'.
        ev_resmsg  = |Please scan highest-level HU.|.
      ELSE.
        " Exists in master but not in EWM stock → doesn't exist
        ev_restype = 'E'.
        ev_resmsg  = |HU { iv_hu } doesn't exist.|.
      ENDIF.
    ELSE.
      " Not found anywhere
      ev_restype = 'E'.
      ev_resmsg  = |HU { iv_hu } doesn't exist.|.
    ENDIF.
  ENDMETHOD.


  " ── CONFIRM ──────────────────────────────────────────────────────────
  " Executes the transfer: move each HU from EWM to IM storage location
  METHOD confirm.
    DATA: lv_count_success TYPE i VALUE 0,
          lv_count_error   TYPE i VALUE 0,
          lv_restype       TYPE char1,
          lv_resmsg        TYPE string,
          lv_hu            TYPE char10,
          lv_err_msgs      TYPE string.

    " Validate destination location first
    me->check_dest(
      EXPORTING iv_destloc = iv_destloc
      IMPORTING ev_restype = lv_restype
                ev_resmsg  = lv_resmsg
    ).

    IF lv_restype = 'E'.
      ev_restype = 'E'.
      ev_resmsg  = lv_resmsg.
      RETURN.
    ENDIF.

    " Check at least one HU
    IF lines( it_hus ) = 0.
      ev_restype = 'E'.
      ev_resmsg  = |At least scan one HU.|.
      RETURN.
    ENDIF.

    " Process each HU
    LOOP AT it_hus INTO lv_hu.
      " Re-validate each HU before transfer
      me->check_hu(
        EXPORTING iv_hu      = lv_hu
        IMPORTING ev_restype = lv_restype
                  ev_resmsg  = lv_resmsg
      ).

      IF lv_restype = 'E'.
        lv_count_error = lv_count_error + 1.
        IF lv_err_msgs IS INITIAL.
          lv_err_msgs = lv_resmsg.
        ELSE.
          lv_err_msgs = lv_err_msgs && '; ' && lv_resmsg.
        ENDIF.
        CONTINUE.
      ENDIF.

      " ─── Actual transfer logic ──────────────────────────────────────
      " TODO: Implement the actual EWM->IM transfer.
      " This typically involves:
      "   1. Create a posting change notice (PCN) in EWM
      "   2. Execute the posting change to move stock to IM
      "   3. Confirm the goods movement
      "
      " Example using BAPI / FM (adjust to actual system):
*     CALL FUNCTION 'Z_EWM_TO_IM_TRANSFER'
*       EXPORTING
*         iv_hu     = lv_hu
*         iv_destloc = iv_destloc
*       EXCEPTIONS
*         error     = 1
*         OTHERS    = 2.
      "
      " For now, placeholder
      lv_count_success = lv_count_success + 1.
    ENDLOOP.

    " Determine result
    IF lv_count_error > 0 AND lv_count_success = 0.
      ev_restype = 'E'.
      ev_resmsg  = lv_err_msgs.
    ELSEIF lv_count_error > 0.
      ev_restype = 'W'.
      ev_resmsg  = |{ lv_count_success } HU(s) transferred. { lv_count_error } failed: { lv_err_msgs }|.
    ELSE.
      ev_restype = 'S'.
      ev_resmsg  = |{ lv_count_success } HU(s) transferred to { iv_destloc } successfully.|.
    ENDIF.
  ENDMETHOD.


  " ── Helper methods ───────────────────────────────────────────────────
  METHOD is_highest_level_hu.
    DATA: lv_parent TYPE char10.

    SELECT SINGLE parenthandlingnumber
      FROM i_handlingunittptp
      INTO lv_parent
      WHERE handlingunitexternalid = iv_hu.

    IF sy-subrc = 0 AND lv_parent IS INITIAL.
      rv_yes = abap_true.
    ELSE.
      rv_yes = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD hu_exists_in_ewm.
    DATA: lv_hu TYPE char10.

    SELECT SINGLE handlingunitnumber
      FROM i_ewm_availablestock
      INTO lv_hu
      WHERE handlingunitnumber = iv_hu.

    rv_yes = boolc( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD hu_exists_in_master.
    DATA: lv_hu TYPE char10.

    SELECT SINGLE handlingunitexternalid
      FROM i_handlingunittptp
      INTO lv_hu
      WHERE handlingunitexternalid = iv_hu.

    rv_yes = boolc( sy-subrc = 0 ).
  ENDMETHOD.

ENDCLASS.
