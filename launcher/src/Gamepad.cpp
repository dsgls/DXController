#include "stdafx.h"
#include "Gamepad.h"

#include <SDL3/SDL.h>

CGamepad::CGamepad()
:m_bInitialized(false)
{
    //No SDL calls here: this runs during CLauncher's member-init phase,
    //before any engine package is loaded, and SDL_Init must not run until
    //Init() (see its comment in Gamepad.h).
}

CGamepad::~CGamepad()
{
    if (m_bInitialized)
    {
        SDL_Quit();
    }
}

bool CGamepad::Init(UViewport* /*pViewport*/)
{
    //Probe for the delay-loaded SDL3.dll before making any SDL call, so a
    //machine without it degrades to gamepad-less instead of failing to
    //start. Keep the handle, never FreeLibrary it -- the delay-load thunks
    //resolve against this same load. Deliberately no SEH here: MSVC rejects
    //__try in functions requiring object unwinding (C2712).
    const HMODULE hSDL = LoadLibraryW(L"SDL3.dll");
    if (!hSDL)
    {
        GLog->Logf(L"Gamepad: SDL3.dll not found -- running gamepad-less.");
        return false;
    }

    if (!SDL_Init(SDL_INIT_GAMEPAD))
    {
        //%hs is an MSVC vswprintf extension for inserting a narrow string
        //into a wide format; SDL_GetError() returns UTF-8/ASCII char*.
        GLog->Logf(L"Gamepad: SDL_Init failed: %hs -- running gamepad-less.", SDL_GetError());
        return false;
    }

    m_bInitialized = true;
    return true;
}
