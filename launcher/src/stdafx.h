#pragma once
#define _WIN32_WINNT _WIN32_WINNT_VISTA
//Can't use WIN32_LEAN_AND_MEAN

#pragma warning(push,0)

//MS
#include <Windows.h>
#include <Windowsx.h>
#include <Shlwapi.h>
#include <CommCtrl.h>
#include <ShlObj.h>
#include <Uxtheme.h>

//C/C++
#include <algorithm>
#include <vector>
#include <deque>
#include <cmath>
#include <string>
#include <limits>
#include <array>
#include <list>
#include <memory>
#include <cassert>
#include <unordered_map>

//Unreal
#include <Engine.h>
#include <Window.h>
#include <FMallocWindows.h>
#include <FOutputDeviceFile.h>
#include <FOutputDeviceWindowsError.h>
#include <FFeedbackContextWindows.h>
#include <UnRender.h>
#include <FConfigCacheIni.h>
#include <FFileManagerWindows.h>

#include <Extension.h>
#include <DeusEx.h>

#pragma warning(pop)

//Version string, generated from git tags at build time. The header holds
//narrow literals because res.rc needs them; WIDEN takes two levels because its
//argument is itself a macro.
#include "version_generated.h"
#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)
