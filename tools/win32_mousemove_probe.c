#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned long move_count;
static unsigned long duplicate_count;
static unsigned long segment_pixels;
static POINT previous;
static LARGE_INTEGER frequency;
static LARGE_INTEGER started;
static int dragging;
static unsigned int processing_delay_ms;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg)
    {
    case WM_LBUTTONDOWN:
        SetCapture(hwnd);
        move_count = duplicate_count = segment_pixels = 0;
        previous.x = GET_X_LPARAM(lparam);
        previous.y = GET_Y_LPARAM(lparam);
        QueryPerformanceCounter(&started);
        dragging = 1;
        return 0;
    case WM_MOUSEMOVE:
        if (dragging && (wparam & MK_LBUTTON))
        {
            POINT current;
            HDC dc;
            current.x = GET_X_LPARAM(lparam);
            current.y = GET_Y_LPARAM(lparam);
            if (current.x == previous.x && current.y == previous.y) duplicate_count++;
            segment_pixels += (unsigned long)(abs(current.x - previous.x) + abs(current.y - previous.y));
            move_count++;
            dc = GetDC(hwnd);
            MoveToEx(dc, previous.x, previous.y, NULL);
            LineTo(dc, current.x, current.y);
            ReleaseDC(hwnd, dc);
            previous = current;
            if (processing_delay_ms) Sleep(processing_delay_ms);
        }
        return 0;
    case WM_LBUTTONUP:
        if (dragging)
        {
            LARGE_INTEGER now;
            double elapsed_ms;
            QueryPerformanceCounter(&now);
            elapsed_ms = (now.QuadPart - started.QuadPart) * 1000.0 / frequency.QuadPart;
            fprintf(stdout,
                    "PROBE: received=%lu duplicates=%lu manhattan_pixels=%lu elapsed_ms=%.3f rate_hz=%.1f\n",
                    move_count, duplicate_count, segment_pixels, elapsed_ms,
                    elapsed_ms > 0.0 ? move_count * 1000.0 / elapsed_ms : 0.0);
            fflush(stdout);
            dragging = 0;
            ReleaseCapture();
        }
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wparam, lparam);
}

int main(void)
{
    const char class_name[] = "AnimateP11MouseProbe";
    WNDCLASSA wc = {0};
    MSG msg;
    HWND hwnd;
    char delay_text[32];
    QueryPerformanceFrequency(&frequency);
    if (GetEnvironmentVariableA("PROBE_DELAY_MS", delay_text, sizeof(delay_text)))
        processing_delay_ms = (unsigned int)strtoul(delay_text, NULL, 10);
    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, IDC_CROSS);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = class_name;
    if (!RegisterClassA(&wc)) return 2;
    hwnd = CreateWindowExA(0, class_name, "Wine WM_MOUSEMOVE probe",
                           WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                           CW_USEDEFAULT, CW_USEDEFAULT, 900, 600,
                           NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) return 3;
    fprintf(stdout, "PROBE: ready hwnd=%p delay_ms=%u\n", (void *)hwnd, processing_delay_ms);
    fflush(stdout);
    while (GetMessageA(&msg, NULL, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return 0;
}
