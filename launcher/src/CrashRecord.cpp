#include "CrashRecord.h"

namespace
{
    //Cursor into the caller's buffer. Every write clamps to the buffer, so a line
    //that does not fit is truncated instead of overrunning; the terminator is
    //written by Finish().
    struct FWriter
    {
        wchar_t* pOut;
        size_t iCapacity; //Excludes the terminator
        size_t iLength;

        void Append(const wchar_t* pszText)
        {
            while (pszText && *pszText && iLength < iCapacity)
            {
                pOut[iLength++] = *pszText++;
            }
        }

        //Fixed-width uppercase hex, "0x" prefixed. iDigits is the field width.
        void AppendHex(const size_t iValue, const size_t iDigits)
        {
            Append(L"0x");
            for (size_t i = iDigits; i > 0; --i)
            {
                const size_t iNibble = (iValue >> ((i - 1) * 4)) & 0xF;
                if (iLength < iCapacity)
                {
                    pOut[iLength++] = static_cast<wchar_t>(iNibble < 10 ? L'0' + iNibble : L'A' + (iNibble - 10));
                }
            }
        }

        void Finish()
        {
            pOut[iLength] = L'\0';
        }
    };

    //Pointers are 8 hex digits on the Win32 x86 build; derived rather than
    //hardcoded so the unit stays honest if it is ever compiled 64-bit.
    constexpr size_t kiAddressDigits = sizeof(void*) * 2;

    size_t AddressValue(const void* const pAddress)
    {
        return reinterpret_cast<size_t>(pAddress);
    }
}

const wchar_t* CrashRecord::ExceptionName(const unsigned long ulExceptionCode)
{
    switch (ulExceptionCode)
    {
    case 0xC0000005ul: return L"EXCEPTION_ACCESS_VIOLATION";
    case 0xC000001Dul: return L"EXCEPTION_ILLEGAL_INSTRUCTION";
    case 0xC0000025ul: return L"EXCEPTION_NONCONTINUABLE_EXCEPTION";
    case 0xC0000026ul: return L"EXCEPTION_INVALID_DISPOSITION";
    case 0xC000008Cul: return L"EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
    case 0xC000008Dul: return L"EXCEPTION_FLT_DENORMAL_OPERAND";
    case 0xC000008Eul: return L"EXCEPTION_FLT_DIVIDE_BY_ZERO";
    case 0xC0000090ul: return L"EXCEPTION_FLT_INVALID_OPERATION";
    case 0xC0000091ul: return L"EXCEPTION_FLT_OVERFLOW";
    case 0xC0000093ul: return L"EXCEPTION_FLT_UNDERFLOW";
    case 0xC0000094ul: return L"EXCEPTION_INT_DIVIDE_BY_ZERO";
    case 0xC0000095ul: return L"EXCEPTION_INT_OVERFLOW";
    case 0xC0000096ul: return L"EXCEPTION_PRIV_INSTRUCTION";
    case 0xC00000FDul: return L"EXCEPTION_STACK_OVERFLOW";
    case 0xC0000409ul: return L"STATUS_STACK_BUFFER_OVERRUN";
    case 0xC0000374ul: return L"STATUS_HEAP_CORRUPTION";
    case 0x80000003ul: return L"EXCEPTION_BREAKPOINT";
    case 0xE06D7363ul: return L"C++ exception";
    default:           return nullptr;
    }
}

void CrashRecord::FormatException(const unsigned long ulExceptionCode, const void* const pFaultAddress, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.Append(L"Crash: unhandled exception ");
    Writer.AppendHex(static_cast<size_t>(ulExceptionCode), 8);
    if (const wchar_t* const pszName = ExceptionName(ulExceptionCode))
    {
        Writer.Append(L" (");
        Writer.Append(pszName);
        Writer.Append(L")");
    }
    Writer.Append(L" at ");
    Writer.AppendHex(AddressValue(pFaultAddress), kiAddressDigits);
    Writer.Finish();
}

void CrashRecord::FormatModuleOffset(const void* const pFaultAddress, const void* const pModuleBase, const wchar_t* const pszModulePath, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.Append(L"Crash: faulting module ");

    const size_t iFault = AddressValue(pFaultAddress);
    const size_t iBase = AddressValue(pModuleBase);
    if (iBase == 0 || iBase > iFault) //Nothing resolved, or a base that cannot own this address
    {
        Writer.Append(L"unknown (address ");
        Writer.AppendHex(iFault, kiAddressDigits);
        Writer.Append(L")");
    }
    else
    {
        Writer.Append((pszModulePath && *pszModulePath) ? pszModulePath : L"(unknown path)");
        Writer.Append(L" + ");
        Writer.AppendHex(iFault - iBase, kiAddressDigits);
    }
    Writer.Finish();
}
