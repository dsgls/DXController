#pragma once

//Log output device that flushes the underlying file after every line.
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
        FOutputDeviceFile::Serialize(Data, Event);
        if (LogAr)
            LogAr->Flush();
    }
};
