#pragma once

//Pushed to warning level 0 the way stdafx.h does it: this header may be
//included without stdafx.h's own windows.h having come first yet.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

bool RegisterRawInput(const HWND hWnd);
