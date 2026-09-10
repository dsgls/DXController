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
    Writer.Append(L"Crash: exception ");
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

namespace
{
    //Decimal without the CRT, for the same crashed-context reason as the hex writer.
    void AppendDecimal(FWriter& Writer, unsigned long long ullValue)
    {
        wchar_t szDigits[24];
        size_t iCount = 0;
        do
        {
            szDigits[iCount++] = static_cast<wchar_t>(L'0' + (ullValue % 10));
            ullValue /= 10;
        } while (ullValue != 0);
        while (iCount > 0)
        {
            const wchar_t szOne[2] = { szDigits[--iCount], L'\0' };
            Writer.Append(szOne);
        }
    }

    const wchar_t* FileNamePart(const wchar_t* const pszPath)
    {
        const wchar_t* pszName = pszPath;
        for (const wchar_t* p = pszPath; p && *p; ++p)
        {
            if (*p == L'\\' || *p == L'/')
            {
                pszName = p + 1;
            }
        }
        return pszName;
    }
}

void CrashRecord::FormatOrigin(const bool bFirstChance, const unsigned long ulThreadId, const unsigned long long ullAgeMs, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    if (bFirstChance)
    {
        Writer.Append(L"Crash: fault recorded first-chance on thread ");
        AppendDecimal(Writer, ulThreadId);
        Writer.Append(L", ");
        AppendDecimal(Writer, ullAgeMs);
        Writer.Append(L" ms before this report");
    }
    else
    {
        Writer.Append(L"Crash: fault reached the unhandled-exception filter on thread ");
        AppendDecimal(Writer, ulThreadId);
    }
    Writer.Finish();
}

void CrashRecord::FormatBreadcrumbs(const wchar_t* const pszMap, const unsigned long long ullMapAgeMs, const wchar_t* const pszStage, const unsigned long long ullStageAgeMs, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.Append(L"Crash: ");
    if (pszMap && *pszMap)
    {
        Writer.Append(L"map '");
        Writer.Append(pszMap);
        Writer.Append(L"' (set ");
        AppendDecimal(Writer, ullMapAgeMs);
        Writer.Append(L" ms ago)");
    }
    else
    {
        Writer.Append(L"map unknown");
    }
    Writer.Append(L"; ");
    if (pszStage && *pszStage)
    {
        Writer.Append(L"engine stage '");
        Writer.Append(pszStage);
        Writer.Append(L"' (set ");
        AppendDecimal(Writer, ullStageAgeMs);
        Writer.Append(L" ms ago)");
    }
    else
    {
        Writer.Append(L"engine stage none");
    }
    Writer.Finish();
}

void CrashRecord::FormatRegisters(const Registers& Regs, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.Append(L"Crash: registers");
    const struct { const wchar_t* pszName; unsigned long ulValue; } kRegs[] = {
        { L" EIP=", Regs.ulEip }, { L" ESP=", Regs.ulEsp }, { L" EBP=", Regs.ulEbp },
        { L" EAX=", Regs.ulEax }, { L" EBX=", Regs.ulEbx }, { L" ECX=", Regs.ulEcx }, { L" EDX=", Regs.ulEdx },
        { L" ESI=", Regs.ulEsi }, { L" EDI=", Regs.ulEdi }, { L" EFLAGS=", Regs.ulEflags },
    };
    for (const auto& Reg : kRegs)
    {
        Writer.Append(Reg.pszName);
        Writer.AppendHex(Reg.ulValue, 8);
    }
    Writer.Finish();
}

void CrashRecord::FormatFrame(const unsigned int uIndex, const void* const pPc, const void* const pModuleBase, const wchar_t* const pszModulePath, const wchar_t* const pszSymbol, const unsigned long long ullDisplacement, wchar_t* const pOut, const size_t iOutChars)
{
    if (iOutChars == 0)
    {
        return;
    }

    FWriter Writer{ pOut, iOutChars - 1, 0 };
    Writer.Append(L"Crash:   #");
    if (uIndex < 10)
    {
        Writer.Append(L"0");
    }
    AppendDecimal(Writer, uIndex);
    Writer.Append(L" ");
    const size_t iPc = AddressValue(pPc);
    Writer.AppendHex(iPc, kiAddressDigits);
    Writer.Append(L" ");

    const size_t iBase = AddressValue(pModuleBase);
    if (iBase == 0 || iBase > iPc)
    {
        Writer.Append(L"unknown");
    }
    else
    {
        const wchar_t* const pszName = FileNamePart(pszModulePath);
        Writer.Append((pszName && *pszName) ? pszName : L"(unknown path)");
        Writer.Append(L"+");
        Writer.AppendHex(iPc - iBase, kiAddressDigits);
    }

    if (pszSymbol && *pszSymbol)
    {
        Writer.Append(L" ");
        Writer.Append(pszSymbol);
        Writer.Append(L"+0x");
        //Displacement is short; no fixed width, so strip leading zeros of a 16-digit field.
        wchar_t szHex[24];
        FWriter Hex{ szHex, 23, 0 };
        Hex.AppendHex(static_cast<size_t>(ullDisplacement), 8);
        Hex.Finish();
        const wchar_t* p = szHex + 2; //Past "0x"
        while (*p == L'0' && *(p + 1) != L'\0')
        {
            ++p;
        }
        Writer.Append(p);
    }
    Writer.Finish();
}
