#pragma once

#include "CrashContext.h"

//Feedback context that logs the engine's slow-task progress and feeds it to
//the crash report as the "engine stage" breadcrumb. The engine calls
//StatusUpdatef once per serialized object during a load, so only a change of
//text is logged: that is one line per package read, which says how far a map
//load got before it died.
class FFeedbackContextLog : public FFeedbackContextWindows
{
public:
    void BeginSlowTask(const TCHAR* Task, UBOOL StatusWindow, UBOOL Cancelable) override
    {
        if (GLog)
        {
            GLog->Logf(L"Engine: slow task '%s' begins.", Task ? Task : L"");
        }
        CrashContext::SetStage(Task);
        m_szLastStatus[0] = L'\0';
        FFeedbackContextWindows::BeginSlowTask(Task, StatusWindow, Cancelable);
    }

    void EndSlowTask() override
    {
        FFeedbackContextWindows::EndSlowTask();
        if (GLog)
        {
            GLog->Log(L"Engine: slow task ends.");
        }
        if (SlowTaskCount == 0) //Tasks nest; the stage stays meaningful while an outer one runs
        {
            CrashContext::SetStage(nullptr);
        }
    }

    UBOOL VARARGS StatusUpdatef(INT Numerator, INT Denominator, const TCHAR* Fmt, ...) override
    {
        TCHAR szText[4096];
        GET_VARARGS(szText, ARRAY_COUNT(szText), Fmt);

        if (wcsncmp(szText, m_szLastStatus, ARRAY_COUNT(m_szLastStatus) - 1) != 0)
        {
            wcsncpy_s(m_szLastStatus, szText, _TRUNCATE);
            if (GLog)
            {
                GLog->Logf(L"Engine: %s", szText);
            }
            CrashContext::SetStage(szText);
        }

        return FFeedbackContextWindows::StatusUpdatef(Numerator, Denominator, L"%s", szText);
    }

private:
    wchar_t m_szLastStatus[256] = {};
};
