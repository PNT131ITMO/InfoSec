#define NOMINMAX
#define _WIN32_WINNT 0x0600

#include <windows.h>
#include <iostream>
#include <string>
#include <vector>
#include <limits>
std::string WideToUtf8(const std::wstring& text)
{
    if (text.empty())
        return {};

    int size = WideCharToMultiByte(
        CP_UTF8,
        0,
        text.c_str(),
        static_cast<int>(text.size()),
        nullptr,
        0,
        nullptr,
        nullptr
    );

    std::string result(size, '\0');

    WideCharToMultiByte(
        CP_UTF8,
        0,
        text.c_str(),
        static_cast<int>(text.size()),
        result.data(),
        size,
        nullptr,
        nullptr
    );

    return result;
}

std::wstring Utf8ToWide(const std::string& text)
{
    if (text.empty())
        return {};

    int size = MultiByteToWideChar(
        CP_UTF8,
        0,
        text.c_str(),
        static_cast<int>(text.size()),
        nullptr,
        0
    );

    std::wstring result(size, L'\0');

    MultiByteToWideChar(
        CP_UTF8,
        0,
        text.c_str(),
        static_cast<int>(text.size()),
        result.data(),
        size
    );

    return result;
}

std::wstring GetWin32Error(DWORD errorCode)
{
    wchar_t* buffer = nullptr;

    FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        errorCode,
        0,
        reinterpret_cast<LPWSTR>(&buffer),
        0,
        nullptr
    );

    std::wstring message = buffer ? buffer : L"Unknown error";

    if (buffer)
        LocalFree(buffer);

    return message;
}

std::wstring MakeStreamPath(
    const std::wstring& fileName,
    const std::wstring& streamName)
{
    return fileName + L":" + streamName;
}

bool WriteStream(
    const std::wstring& fileName,
    const std::wstring& streamName,
    const std::wstring& text,
    bool append)
{
    std::wstring streamPath =
        MakeStreamPath(fileName, streamName);

    DWORD creationDisposition =
        append ? OPEN_ALWAYS : CREATE_ALWAYS;

    HANDLE hFile = CreateFileW(
        streamPath.c_str(),
        GENERIC_WRITE,
        FILE_SHARE_READ,
        nullptr,
        creationDisposition,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );

    if (hFile == INVALID_HANDLE_VALUE)
    {
        std::wcerr
            << L"CreateFileW failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        return false;
    }

    if (append)
    {
        LARGE_INTEGER zero{};
        SetFilePointerEx(
            hFile,
            zero,
            nullptr,
            FILE_END
        );
    }

    std::string utf8 = WideToUtf8(text);

    DWORD bytesWritten = 0;

    BOOL result = WriteFile(
        hFile,
        utf8.data(),
        static_cast<DWORD>(utf8.size()),
        &bytesWritten,
        nullptr
    );

    if (!result)
    {
        std::wcerr
            << L"WriteFile failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        CloseHandle(hFile);
        return false;
    }

    CloseHandle(hFile);

    std::wcout
        << L"Written "
        << bytesWritten
        << L" bytes to "
        << streamPath
        << std::endl;

    return true;
}

bool ReadStream(
    const std::wstring& fileName,
    const std::wstring& streamName)
{
    std::wstring streamPath =
        MakeStreamPath(fileName, streamName);

    HANDLE hFile = CreateFileW(
        streamPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );

    if (hFile == INVALID_HANDLE_VALUE)
    {
        std::wcerr
            << L"CreateFileW failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        return false;
    }

    LARGE_INTEGER size{};

    if (!GetFileSizeEx(hFile, &size))
    {
        std::wcerr
            << L"GetFileSizeEx failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        CloseHandle(hFile);
        return false;
    }

    std::vector<char> buffer(
        static_cast<size_t>(size.QuadPart)
    );

    DWORD totalRead = 0;

    while (totalRead < buffer.size())
    {
        DWORD toRead =
            static_cast<DWORD>(
                std::min<size_t>(
                    buffer.size() - totalRead,
                    std::numeric_limits<DWORD>::max()
                )
            );

        DWORD bytesRead = 0;

        if (!ReadFile(
                hFile,
                buffer.data() + totalRead,
                toRead,
                &bytesRead,
                nullptr))
        {
            std::wcerr
                << L"ReadFile failed: "
                << GetWin32Error(GetLastError())
                << std::endl;

            CloseHandle(hFile);
            return false;
        }

        if (bytesRead == 0)
            break;

        totalRead += bytesRead;
    }

    CloseHandle(hFile);

    std::string utf8(
        buffer.begin(),
        buffer.begin() + totalRead
    );

    std::wcout << L"\n----- STREAM CONTENT -----\n";
    std::wcout << Utf8ToWide(utf8);
    std::wcout << L"\n--------------------------\n";

    return true;
}

bool ShowStreamSize(
    const std::wstring& fileName,
    const std::wstring& streamName)
{
    std::wstring streamPath =
        MakeStreamPath(fileName, streamName);

    HANDLE hFile = CreateFileW(
        streamPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr
    );

    if (hFile == INVALID_HANDLE_VALUE)
    {
        std::wcerr
            << L"Cannot open stream: "
            << GetWin32Error(GetLastError())
            << std::endl;

        return false;
    }

    LARGE_INTEGER size{};

    if (!GetFileSizeEx(hFile, &size))
    {
        std::wcerr
            << L"GetFileSizeEx failed."
            << std::endl;

        CloseHandle(hFile);
        return false;
    }

    CloseHandle(hFile);

    std::wcout
        << L"Stream size: "
        << size.QuadPart
        << L" bytes"
        << std::endl;

    return true;
}

bool DeleteStream(
    const std::wstring& fileName,
    const std::wstring& streamName)
{
    std::wstring streamPath =
        MakeStreamPath(fileName, streamName);

    if (!DeleteFileW(streamPath.c_str()))
    {
        std::wcerr
            << L"DeleteFileW failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        return false;
    }

    std::wcout
        << L"Stream deleted successfully."
        << std::endl;

    return true;
}

void ListStreams(const std::wstring& fileName)
{
    WIN32_FIND_STREAM_DATA streamData{};

    HANDLE hFind = FindFirstStreamW(
        fileName.c_str(),
        FindStreamInfoStandard,
        &streamData,
        0
    );

    if (hFind == INVALID_HANDLE_VALUE)
    {
        std::wcerr
            << L"FindFirstStreamW failed: "
            << GetWin32Error(GetLastError())
            << std::endl;

        return;
    }

    std::wcout << L"\nStreams of " << fileName << L":\n";

    do
    {
        std::wcout
            << L"  "
            << streamData.cStreamName
            << L"    "
            << streamData.StreamSize.QuadPart
            << L" bytes"
            << std::endl;

    } while (FindNextStreamW(
        hFind,
        &streamData
    ));

    FindClose(hFind);
}

int main()
{
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);

    std::wstring fileName;

    std::wcout
        << L"Enter NTFS file path "
        << L"[default D:\\test.txt]: ";

    std::getline(std::wcin, fileName);

    if (fileName.empty())
        fileName = L"D:\\test.txt";

    while (true)
    {
        std::wcout
            << L"\n========== NTFS ADS TOOL ==========\n"
            << L"1. Write / overwrite stream\n"
            << L"2. Read stream\n"
            << L"3. Append to stream\n"
            << L"4. Get stream size\n"
            << L"5. List all streams\n"
            << L"6. Delete stream\n"
            << L"0. Exit\n"
            << L"===================================\n"
            << L"Choice: ";

        int choice;
        std::wcin >> choice;

        std::wcin.ignore(
            std::numeric_limits<std::streamsize>::max(),
            L'\n'
        );

        if (choice == 0)
            break;

        if (choice == 5)
        {
            ListStreams(fileName);
            continue;
        }

        std::wstring streamName;

        std::wcout << L"Stream name: ";
        std::getline(std::wcin, streamName);

        switch (choice)
        {
        case 1:
        {
            std::wstring text;

            std::wcout << L"Text to write: ";
            std::getline(std::wcin, text);

            WriteStream(
                fileName,
                streamName,
                text,
                false
            );

            break;
        }

        case 2:
            ReadStream(
                fileName,
                streamName
            );
            break;

        case 3:
        {
            std::wstring text;

            std::wcout << L"Text to append: ";
            std::getline(std::wcin, text);

            WriteStream(
                fileName,
                streamName,
                text,
                true
            );

            break;
        }

        case 4:
            ShowStreamSize(
                fileName,
                streamName
            );
            break;

        case 6:
            DeleteStream(
                fileName,
                streamName
            );
            break;

        default:
            std::wcout
                << L"Unknown command."
                << std::endl;
        }
    }

    return 0;
}