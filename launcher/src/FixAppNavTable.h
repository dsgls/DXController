#pragma once

#include "PadNavGraph.h"
#include "resource.h"

//For IDOK/IDCANCEL only. Pushed to warning level 0 the way stdafx.h does it:
//this header is also compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

//Spatial navigation graph for IDD_FIXAPP, matching the two-column layout in
//res.rc. Order: control, up, down, left, right (0 = no move). Edges are
//intentionally asymmetric where a wide control faces several neighbours.
//Disabled controls are skipped at runtime. Lives in a header so
//FixAppNavTableTests can check the real table for typo'd and orphaned ids.
static constexpr SPadNavEntry kFixAppNavTable[] =
{
    { CHK_NOMOUSEACCEL,          0,                         CHK_SUBTITLEFIX,           0,                         TXT_LATENCY },
    { CHK_SUBTITLEFIX,           CHK_NOMOUSEACCEL,          CHK_GUIFIX,                0,                         CHK_DIRECTSOUND },
    { CHK_GUIFIX,                CHK_SUBTITLEFIX,           COMBO_RENDERER,            0,                         COMBO_GUISCALING },
    { COMBO_GUISCALING,          CHK_SUBTITLEFIX,           COMBO_RENDERER,            CHK_GUIFIX,                CHK_USESINGLECPU },
    { TXT_LATENCY,               0,                         CHK_DIRECTSOUND,           CHK_NOMOUSEACCEL,          0 },
    { CHK_DIRECTSOUND,           TXT_LATENCY,               CHK_USESINGLECPU,          CHK_SUBTITLEFIX,           0 },
    { CHK_USESINGLECPU,          CHK_DIRECTSOUND,           RADIO_16BIT,               COMBO_GUISCALING,          0 },
    { COMBO_RENDERER,            CHK_GUIFIX,                TXT_FPSLIMIT,              0,                         RADIO_16BIT },
    { TXT_FPSLIMIT,              COMBO_RENDERER,            RADIO_VPWINDOWED,          0,                         RADIO_32BIT },
    { RADIO_16BIT,               CHK_USESINGLECPU,          RADIO_32BIT,               COMBO_RENDERER,            CHK_DETAILTEX },
    { CHK_DETAILTEX,             CHK_USESINGLECPU,          RADIO_32BIT,               RADIO_16BIT,               0 },
    { RADIO_32BIT,               RADIO_16BIT,               RADIO_FOVDEFAULT,          TXT_FPSLIMIT,              0 },
    { RADIO_VPWINDOWED,          TXT_FPSLIMIT,              RADIO_VPFULLSCREEN,        0,                         RADIO_FOVDEFAULT },
    { RADIO_VPFULLSCREEN,        RADIO_VPWINDOWED,          RADIO_VPBORDERLESS,        0,                         RADIO_FOVAUTO },
    { RADIO_VPBORDERLESS,        RADIO_VPFULLSCREEN,        RADIO_RESCOMMON,           0,                         CHK_BORDERLESSALLMONITORS },
    { CHK_BORDERLESSALLMONITORS, RADIO_VPFULLSCREEN,        COMBO_RESOLUTION,          RADIO_VPBORDERLESS,        RADIO_FOVCUSTOM },
    { RADIO_FOVDEFAULT,          RADIO_32BIT,               RADIO_FOVAUTO,             RADIO_VPWINDOWED,          0 },
    { RADIO_FOVAUTO,             RADIO_FOVDEFAULT,          RADIO_FOVCUSTOM,           RADIO_VPFULLSCREEN,        0 },
    { RADIO_FOVCUSTOM,           RADIO_FOVAUTO,             IDOK,                      CHK_BORDERLESSALLMONITORS, TXT_FOV },
    { TXT_FOV,                   RADIO_FOVAUTO,             IDCANCEL,                  RADIO_FOVCUSTOM,           0 },
    { RADIO_RESCOMMON,           RADIO_VPBORDERLESS,        RADIO_RESCUSTOM,           0,                         COMBO_RESOLUTION },
    { COMBO_RESOLUTION,          CHK_BORDERLESSALLMONITORS, TXT_RESX,                  RADIO_RESCOMMON,           0 },
    { RADIO_RESCUSTOM,           RADIO_RESCOMMON,           IDOK,                      0,                         TXT_RESX },
    { TXT_RESX,                  COMBO_RESOLUTION,          IDOK,                      RADIO_RESCUSTOM,           TXT_RESY },
    { TXT_RESY,                  COMBO_RESOLUTION,          IDOK,                      TXT_RESX,                  0 },
    { IDOK,                      RADIO_FOVCUSTOM,           0,                         TXT_RESY,                  IDCANCEL },
    { IDCANCEL,                  TXT_FOV,                   0,                         IDOK,                      0 },
};

//Focus target when the pad navigates while focus is outside the table.
static constexpr int kFixAppNavHome = CHK_NOMOUSEACCEL;
