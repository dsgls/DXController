#include "LogTime.h"

namespace
{
    //Cursor into the caller's buffer, same truncate-don't-overrun shape as
    //CrashRecord's FWriter.
    struct FWriter
    {
        wchar_t* pOut;
        size_t iCapacity; //Excludes the terminator
        size_t iLength;

        void AppendChar(const wchar_t ch)
        {
            if (iLength < iCapacity)
            {
                pOut[iLength++] = ch;
            }
        }

        //Zero-padded fixed-width decimal.
        void AppendDigits(unsigned int iValue, const int iDigits)
        {
            wchar_t Digits[4]; //Largest field here is milliseconds, 3 digits
            for (int i = iDigits - 1; i >= 0; --i)
            {
                Digits[i] = static_cast<wchar_t>(L'0' + (iValue % 10));
                iValue /= 10;
            }
            for (int i = 0; i < iDigits; ++i)
            {
                AppendChar(Digits[i]);
            }
        }

        void Finish()
        {
            pOut[iLength] = L'\0';
        }
    };
}

void LogTime::FormatPrefix(const SYSTEMTIME& st, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.AppendChar(L'[');
    Writer.AppendDigits(st.wHour, 2);
    Writer.AppendChar(L':');
    Writer.AppendDigits(st.wMinute, 2);
    Writer.AppendChar(L':');
    Writer.AppendDigits(st.wSecond, 2);
    Writer.AppendChar(L'.');
    Writer.AppendDigits(st.wMilliseconds, 3);
    Writer.AppendChar(L']');
    Writer.AppendChar(L' ');
    Writer.Finish();
}
