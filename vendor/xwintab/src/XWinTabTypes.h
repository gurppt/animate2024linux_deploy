
#pragma once

typedef enum EventTypeTAG {
    kEventTypeUnknown = 0,
    kEventTypeButtonPress = 1,
    kEventTypeButtonRelease = 2,
    kEventTypeProximityIn = 3,
    kEventTypeProximityOut = 4,
    kEventTypeMotionNotify = 5
} EventType;

typedef struct EventInfoTAG {
    EventType type;
    unsigned int time;
    int x;
    int y;
    int pressure;
    int xTilt;
    int yTilt;
    unsigned int buttonsState;
} EventInfo;

typedef void (WINAPI *EventCallback)(EventInfo *);

typedef struct AxisInfoTAG {
    int min;
    int max;
    unsigned int resolution;
} AxisInfo;

typedef struct DeviceInfoTAG {
    int id;
    AxisInfo xAxis;
    AxisInfo yAxis;
    AxisInfo pressureAxis;
    int nButtons;
    int hasTilt;
} DeviceInfo;
