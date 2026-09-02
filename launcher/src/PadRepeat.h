#pragma once

//For WORD/ULONGLONG only. Pushed to warning level 0 the way stdafx.h does it:
//this header is also compiled into the test project, which builds at /W4 /WX.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

//Keyboard-style auto-repeat for held d-pad directions, as a pure state
//transition: the caller owns the four SRepeatState slots and the button
//bitmask layout, and acts on the directions Tick() reports as fired.
namespace PadRepeat
{
    constexpr ULONGLONG kRepeatDelayMs    = 400;
    constexpr ULONGLONG kRepeatIntervalMs = 100;

    struct SRepeatState
    {
        bool      bDown;
        ULONGLONG iNextFireMs;
    };

    //aDirBits gives the caller's mask for each of the four directions, in the
    //same order as the state and output arrays. A direction fires on its press
    //edge and then every kRepeatIntervalMs once kRepeatDelayMs has elapsed;
    //releasing it resets the slot.
    void Tick(SRepeatState (&aState)[4], const WORD (&aDirBits)[4], WORD iPrevButtons,
              WORD iButtons, ULONGLONG iNowMs, bool (&bFired)[4]);
}
