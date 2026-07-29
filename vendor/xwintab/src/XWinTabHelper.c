//
// This is native Linux code that our WinTab DLL will call into. The entrypoints
// are at the bottom of the file.
//
// Currently this code uses XInput 1 functionality via libxcb. This keeps us
// seperate from the libX11 used by Wine since that maintains per-process error
// handling information.
//

#include <ctype.h>
#include <stdio.h>
#include <stdio.h>
#include <stdio.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <windef.h>

// WineGCC defines _WIN32 for us to use any windows headers but XCB has
// different headers on Windows and we want the unix version.
#undef _WIN32
#include <xcb/xcb.h>
#include <xcb/xinput.h>
#define _WIN32 1

#include <sys/poll.h>

#include "XWinTabTypes.h"


typedef struct HelperDataTAG {
    DeviceInfo device;
    xcb_connection_t *connection;
    EventCallback callback;
    uint8_t xiEventBase;
} HelperData;

static HelperData g_data;

static EventInfo g_eventInfo;

static const char *g_requiredName;


// ----------------
// XCB Event Handling
//

static void handle_event(xcb_generic_event_t *xcb_event) {
    const uint8_t kDeviceIDMask = 0x7f;
    const uint8_t kMoreEventsMask = 0x80;

    EventType type = kEventTypeUnknown;
    uint8_t ev_type = xcb_event->response_type - g_data.xiEventBase;

    switch (ev_type) {
    case XCB_INPUT_DEVICE_BUTTON_PRESS:
        type = kEventTypeButtonPress;
        break;
    case XCB_INPUT_DEVICE_BUTTON_RELEASE:
        type = kEventTypeButtonRelease;
        break;
    case XCB_INPUT_PROXIMITY_IN:
        type = kEventTypeProximityIn;
        break;
    case XCB_INPUT_PROXIMITY_OUT:
        type = kEventTypeProximityOut;
        break;
    case XCB_INPUT_DEVICE_MOTION_NOTIFY:
        type = kEventTypeMotionNotify;
        break;
    case XCB_INPUT_DEVICE_VALUATOR:
        break;
    default:
        return;
    }

    if (ev_type == XCB_INPUT_DEVICE_VALUATOR) {
        // We should be sent a device valuator event directly after receiving
        // one of the events we selected.
        xcb_input_device_valuator_event_t *event;
        event = (xcb_input_device_valuator_event_t *) xcb_event;

        if (event->device_id != g_data.device.id || !g_eventInfo.type)
            return;

        if (event->first_valuator != 0) {
            // You may be sent multiple valuator events if the number of axes
            // doesn't fit into one event. We are only interested in the first
            // set of axes.
            g_eventInfo.type = kEventTypeUnknown;
            return;
        }

        if (event->num_valuators > 4)
            g_eventInfo.yTilt = event->valuators[4];
        if (event->num_valuators > 3)
            g_eventInfo.xTilt = event->valuators[3];
        g_eventInfo.x = event->valuators[0];
        g_eventInfo.y = event->valuators[1];
        g_eventInfo.pressure = event->valuators[2];
    }
    else {
        // All our selected events have the same structure
        xcb_input_device_key_press_event_t *event;
        event = (xcb_input_device_key_press_event_t *) xcb_event;

        if ((event->device_id & kDeviceIDMask) != g_data.device.id)
            return;

        g_eventInfo.x = 0;
        g_eventInfo.y = 0;
        g_eventInfo.pressure = 0;
        g_eventInfo.xTilt = 0;
        g_eventInfo.yTilt = 0;

        g_eventInfo.type = type;
        g_eventInfo.time = event->time;

        if (ev_type == XCB_INPUT_DEVICE_BUTTON_PRESS) {
            if (event->detail > 0 && event->detail < 32)
                g_eventInfo.buttonsState |= 1 << (event->detail - 1);
        }

        if (ev_type == XCB_INPUT_DEVICE_BUTTON_RELEASE) {
            if (event->detail > 0 && event->detail < 32)
                g_eventInfo.buttonsState &= ~(1 << (event->detail - 1));
        }

        if (event->device_id & kMoreEventsMask)
            return;
    }

    g_data.callback(&g_eventInfo);
    g_eventInfo.type = kEventTypeUnknown;
}

static int check_events(unsigned int timeout) {
    int conn_fd = xcb_get_file_descriptor(g_data.connection);

    struct pollfd poll_fd;
    poll_fd.fd = conn_fd;
    poll_fd.events = POLLIN;

    poll(&poll_fd, 1, timeout);

    xcb_generic_event_t *xcb_event = NULL;
    while (xcb_event = xcb_poll_for_event(g_data.connection)) {
        // Errors have a response type of 0.
        // We are only interested in events that can be in the
        // event base allocated to the XInput extension.
        if (xcb_event->response_type < g_data.xiEventBase)
            continue;
        handle_event(xcb_event);
    }

    return !xcb_connection_has_error(g_data.connection);
}


// ----------------
// Event Subscription
//

static int get_event_classes(xcb_input_event_class_t *classes) {
    int has_button = 0;
    int has_proximity = 0;
    int has_valuator = 0;
    int count = 0;

    // We're supposed to get the event base for each class on a per device basis
    // but if the XInput library is going to cheat, so will we. The events all
    // have a fixed offset relative to the same event_base.

    // No free(), reply data belongs to cache.
    const xcb_query_extension_reply_t *ext_info;
    ext_info = xcb_get_extension_data(g_data.connection, &xcb_input_id);
    int base = g_data.xiEventBase = ext_info->first_event;

    uint8_t device_id = (uint8_t) g_data.device.id;

    // We will leave the device open to receive events about it.
    xcb_input_open_device_cookie_t cookie;
    cookie = xcb_input_open_device(g_data.connection, device_id);

    xcb_input_open_device_reply_t *reply;
    xcb_generic_error_t *error;
    reply = xcb_input_open_device_reply(g_data.connection, cookie, &error);

    if (error) return 0;

    xcb_input_input_class_info_t *info;
    info = xcb_input_open_device_class_info(reply);

    // SelectExtensionEvent wants a list of event numbers or'd with the device
    // ID. The events are offset by the event base. That's what the macros in
    // the XInput headers are doing.
    for (int i = 0; i < reply->num_classes; i++) {
        xcb_input_event_class_t cls = (g_data.device.id << 8) | base;

        if (info[i].class_id == XCB_INPUT_INPUT_CLASS_BUTTON) {
            if (has_button) continue;
            has_button = 1;

            classes[count++] = cls + XCB_INPUT_DEVICE_BUTTON_PRESS;
            classes[count++] = cls + XCB_INPUT_DEVICE_BUTTON_RELEASE;
        }
        else if (info[i].class_id == XCB_INPUT_INPUT_CLASS_PROXIMITY) {
            if (has_proximity) continue;
            has_proximity = 1;

            classes[count++] = cls + XCB_INPUT_PROXIMITY_IN;
            classes[count++] = cls + XCB_INPUT_PROXIMITY_OUT;
        }
        else if (info[i].class_id == XCB_INPUT_INPUT_CLASS_VALUATOR) {
            if (has_valuator) continue;
            has_valuator = 1;

            classes[count++] = cls + XCB_INPUT_DEVICE_MOTION_NOTIFY;
        }
    }

    free(reply);
    return count;
}

static int select_events() {
    int num_classes = 0;
    xcb_input_event_class_t event_classes[5];

    num_classes = get_event_classes(event_classes);
    if (!num_classes)
        return 0;

    const xcb_setup_t *setup = xcb_get_setup(g_data.connection);
    if (!setup->roots_len)
        return 0;

    xcb_screen_iterator_t screen_itr = xcb_setup_roots_iterator(setup);
    xcb_window_t window = screen_itr.data->root;

    xcb_input_select_extension_event(g_data.connection, window,
                                        num_classes, event_classes);

    xcb_flush(g_data.connection);
    return 1;
}


// ----------------
// Connection Setup and Device Selection.
//

static int match_token(xcb_str_t *name, const char *match) {
    const char *p, *q, *end;
    p = xcb_str_name(name);
    end = p + xcb_str_name_length(name);

    while (p != end) {
        while (p != end && isspace(*p))
            p++;
        if (p == end)
            break;

        for (q = match; *q && p != end && tolower(*p) == tolower(*q); q++)
            p++;
        if (!*q && (p == end || isspace(*p) || *p == ':'))
            return 1;

        while (p != end && ! isspace(*p))
            p++;
    }
    return 0;
}

static int check_device(const xcb_input_device_info_t *device,
                        const xcb_input_input_info_iterator_t *inputItr,
                        xcb_str_t *name) {
    if (device->device_use != XCB_INPUT_DEVICE_USE_IS_X_EXTENSION_DEVICE &&
        device->device_use != XCB_INPUT_DEVICE_USE_IS_X_EXTENSION_KEYBOARD &&
        device->device_use != XCB_INPUT_DEVICE_USE_IS_X_EXTENSION_POINTER)
        return 0;

    if (!g_requiredName) {
        if (!match_token(name, "stylus") && !match_token(name, "pen"))
            return 0;
    } else {
        const char *name_p = xcb_str_name(name);
        int name_len = xcb_str_name_length(name);
        if (name_len != strlen(g_requiredName) ||
            strncmp(name_p, g_requiredName, name_len))
            return 0;
    }

    int class_count = device->num_class_info;
    xcb_input_input_info_iterator_t input_itr = *inputItr;

    xcb_input_button_info_t *button_info = NULL;
    xcb_input_valuator_info_t *valuator_info = NULL;
    while (class_count-- > 0) {
        if (input_itr.data->class_id == XCB_INPUT_INPUT_CLASS_BUTTON)
            button_info = (xcb_input_button_info_t *) input_itr.data;
        else if (input_itr.data->class_id == XCB_INPUT_INPUT_CLASS_VALUATOR)
            valuator_info = (xcb_input_valuator_info_t *) input_itr.data;

        if (input_itr.rem == 0)
            break;
        xcb_input_input_info_next(&input_itr);
    }

    const int kMinStylusAxis = 3;
    if (!valuator_info ||
        valuator_info->axes_len < kMinStylusAxis)
        return 0;

    // Ok, this is probably a tablet stylus.
    g_data.device.id = device->device_id;

    xcb_input_axis_info_t *axis = xcb_input_valuator_info_axes(valuator_info);
    AxisInfo *dev_axis = &g_data.device.xAxis;
    for (int i = 0; i < kMinStylusAxis; i++) {
        dev_axis[i].min = axis[i].minimum;
        dev_axis[i].max = axis[i].maximum;
        dev_axis[i].resolution = axis[i].resolution;
    }

    g_data.device.nButtons = button_info ? (button_info->num_buttons > 32 ? 32 : button_info->num_buttons) : 0;
    g_data.device.hasTilt = valuator_info->axes_len > 4 ? 1 : 0;

    return 1;
}

static void check_devices(const xcb_input_list_input_devices_reply_t *r) {
    xcb_input_device_info_iterator_t dev_itr;
    xcb_input_input_info_iterator_t input_itr;
    xcb_str_iterator_t name_itr;

    int count = xcb_input_list_input_devices_devices_length(r);
    if (!count)
        return;

    dev_itr = xcb_input_list_input_devices_devices_iterator(r);
    input_itr = xcb_input_list_input_devices_infos_iterator(r);
    name_itr = xcb_input_list_input_devices_names_iterator(r);

    while (1) {
        xcb_input_device_info_t *dev = dev_itr.data;
        xcb_input_input_info_t *input = input_itr.data;
        xcb_str_t *name = name_itr.data;

        // input_itr is passed const here.
        fprintf(stderr, "XWINTAB-SCAN: dev id=%d use=%d name=%.*s classes=%d\n", dev->device_id, dev->device_use, xcb_str_name_length(name), xcb_str_name(name), dev->num_class_info);
        if (check_device(dev, &input_itr, name))
            return;

        if (--count == 0) break;

        xcb_input_device_info_next(&dev_itr);
        xcb_str_next(&name_itr);

        // Note that input_itr contains every device's input classes so we have
        // advance it multiple times per device.
        int class_count = dev->num_class_info;
        while (class_count--)
            xcb_input_input_info_next(&input_itr);
    }
}

static int setup() {
    if (!g_data.connection)
        g_data.connection = xcb_connect(NULL, NULL);
    if (xcb_connection_has_error(g_data.connection)) {
        xcb_disconnect(g_data.connection);
        g_data.connection = NULL;
        return 0;
    }

    xcb_input_list_input_devices_cookie_t dev_list_cookie;
    dev_list_cookie = xcb_input_list_input_devices(g_data.connection);

    xcb_generic_error_t *xcb_err = NULL;
    xcb_input_list_input_devices_reply_t *dev_list_reply;
    dev_list_reply = xcb_input_list_input_devices_reply(g_data.connection,
                                                        dev_list_cookie,
                                                        &xcb_err);
    if (xcb_err) {
        xcb_disconnect(g_data.connection);
        g_data.connection = NULL;
        return 0;
    }

    g_requiredName = getenv("XWINTAB_DEVICE");

    g_data.device.id = -1;
    check_devices(dev_list_reply);
    if (g_data.device.id == -1 && g_requiredName) {
        /*
         * Device names can gain/remove a seat suffix between Xorg sessions.
         * Keep the exact-name fast path, then fall back to the conservative
         * stylus/pen token test used when no override is supplied.
         */
        g_requiredName = NULL;
        check_devices(dev_list_reply);
    }

    free(dev_list_reply);
    return 1;
}


// ----------------
// DLL Exports
//

// Start a connection to the X11 server and query device information.
// Returns zero if there was an error. Failure to find a suitable device
// is not considered an error.
int WINAPI Load() {
    return setup();
}

// Check if a suitable device was found and get the needed information.
// Returns NULL if no suitable device was found.
const DeviceInfo* WINAPI GetSelectedDevice() {
    if (g_data.device.id == -1)
        return NULL;
    return &g_data.device;
}

// Open the device and ask the X11 server to send us device events for the
// first root window. The callback function will called when a call to
// CheckEvents() finds a device event.
//
// This is currently only designed to be called once.
//
// Returns 0 if there was an error.
int WINAPI BeginEvents(EventCallback callback) {
    if (g_data.device.id == -1)
        return 0;
    g_data.callback = callback;
    return select_events();
}

// Causes the thread to wait for device events for the specified timeout
// (in milliseconds). Any relevant device events will be passed to the callback
// given in BeginEvents().
//
// This should be called from a background thread so as not to block the main
// UI thread of the Application.
//
// Returns 0 if there was an error.
int WINAPI CheckEvents(unsigned int timeout) {
    return check_events(timeout);
}

// Closes the connection. This should be called after any event handling thread
// has stopped.
int WINAPI Shutdown() {
    if (g_data.connection) {
        xcb_disconnect(g_data.connection);
        g_data.connection = NULL;
    }
    return 1;
}
