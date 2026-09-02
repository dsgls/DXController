#pragma once

//Pushed to warning level 0 the way stdafx.h does it, so this header doesn't
//depend on stdafx.h having included windows.h first.
#pragma warning(push, 0)
#pragma warning(disable: 4324) //SDK structs padded by the launcher project's /Zp4
#include <windows.h>
#pragma warning(pop)

#include <memory>

class CDialogPadNav;

//Plumbing every launcher dialog repeats: the "this" window property that lets
//a static dialog proc find its object, the title-bar icon, and the gamepad
//navigator. A dialog proc calls HandleCommonMessage() before its own switch,
//and Attach() from WM_INITDIALOG.
class CDialogHost
{
public:
    CDialogHost(const CDialogHost&) = delete;
    CDialogHost& operator=(const CDialogHost&) = delete;

protected:
    CDialogHost();
    //Declared here, defaulted in the .cpp: destroying m_pPadNav needs the
    //complete CDialogPadNav, which only the .cpp sees.
    ~CDialogHost();

    //WM_INITDIALOG: bind the object passed as lParam to hwndDlg and set the
    //title-bar icon. Returns that object.
    template<class T> static T* Attach(const HWND hwndDlg, const LPARAM lParam)
    {
        T* const pThis = reinterpret_cast<T*>(lParam);
        BindSelf(hwndDlg, pThis);
        return pThis;
    }

    //The object bound by Attach(), or nullptr before WM_INITDIALOG.
    template<class T> static T* Self(const HWND hwndDlg)
    {
        return static_cast<T*>(FindSelf(hwndDlg));
    }

    //Handles the messages all three dialogs treat identically. Returns true
    //when the proc should return iResult without inspecting the message
    //itself.
    static bool HandleCommonMessage(const HWND hwndDlg, const UINT uMsg, const WPARAM wParam, CDialogHost* const pThis, INT_PTR& iResult);

    std::unique_ptr<CDialogPadNav> m_pPadNav;

private:
    static void BindSelf(const HWND hwndDlg, CDialogHost* const pThis);
    static CDialogHost* FindSelf(const HWND hwndDlg);
};
