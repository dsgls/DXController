#pragma once

#include "LogTime.h"

//Log output device that flushes the underlying file after every line, and
//prepends a "[HH:MM:SS.mmm] " timestamp to every line (lines read
//"Log: [12:34:56.789] message").
//
//The stock FOutputDeviceFile hands each line to an FArchiveFileWriter that
//buffers in a 4 KB user-space buffer and only WriteFile()s on overflow, Seek,
//Close or destruction. On a hard crash the buffered tail is never handed to the
//OS and is lost. (FILEWRITE_Unbuffered, which FOutputDeviceFile already passes,
//is a no-op in FFileManagerWindows.) Flushing per line pushes every line to the
//OS immediately, so the log tail survives a crash.
class FOutputDeviceFileFlush : public FOutputDeviceFile
{
public:
    void Serialize(const TCHAR* Data, enum EName Event)
    {
        //FOutputDeviceFile skips file output for NAME_Title but still
        //forwards Data to GLogHook, which WLog uses as its window caption -
        //a timestamp there would be wrong.
        if (Event == NAME_Title)
        {
            FOutputDeviceFile::Serialize(Data, Event);
            return;
        }

        //On the critical-error path FOutputDeviceFile::Serialize re-enters
        //itself virtually (its own recursion guard calls the unqualified,
        //virtual Serialize on `this`), landing back here with Data already
        //prefixed. Without this guard that second pass would prefix again.
        static UBOOL bReentered = 0;
        if (bReentered)
        {
            FOutputDeviceFile::Serialize(Data, Event);
            if (LogAr)
                LogAr->Flush();
            return;
        }

        //Fixed buffer, not a runtime-sized stack buffer: this path also runs
        //during crash logging (GErrorHist is TCHAR[4096]), so no VLA/alloca.
        static wchar_t szPrefixed[8192];
        SYSTEMTIME st;
        GetLocalTime(&st);
        wchar_t szPrefix[16];
        LogTime::FormatPrefix(st, szPrefix, ARRAY_COUNT(szPrefix));

        size_t iLength = 0;
        const size_t iCapacity = ARRAY_COUNT(szPrefixed) - 16; //Truncate only above 8192-16
        for (const wchar_t* p = szPrefix; *p && iLength < iCapacity; ++p)
            szPrefixed[iLength++] = *p;
        for (const wchar_t* p = Data; p && *p && iLength < iCapacity; ++p)
            szPrefixed[iLength++] = *p;
        szPrefixed[iLength] = L'\0';

        bReentered = 1;
        FOutputDeviceFile::Serialize(szPrefixed, Event);
        bReentered = 0;

        if (LogAr)
            LogAr->Flush();
    }
};
