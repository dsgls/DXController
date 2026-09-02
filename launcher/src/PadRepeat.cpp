#include "PadRepeat.h"

namespace PadRepeat
{

void Tick(SRepeatState (&aState)[4], const WORD (&aDirBits)[4], const WORD iPrevButtons,
          const WORD iButtons, const ULONGLONG iNowMs, bool (&bFired)[4])
{
    const WORD iPressed = static_cast<WORD>(iButtons & ~iPrevButtons);
    for (int i = 0; i < 4; ++i)
    {
        SRepeatState& Repeat = aState[i];
        bFired[i] = false;
        if ((iButtons & aDirBits[i]) == 0)
        {
            Repeat = {};
        }
        else if (iPressed & aDirBits[i])
        {
            Repeat.bDown = true;
            Repeat.iNextFireMs = iNowMs + kRepeatDelayMs;
            bFired[i] = true;
        }
        else if (Repeat.bDown && iNowMs >= Repeat.iNextFireMs)
        {
            Repeat.iNextFireMs = iNowMs + kRepeatIntervalMs;
            bFired[i] = true;
        }
    }
}

}
