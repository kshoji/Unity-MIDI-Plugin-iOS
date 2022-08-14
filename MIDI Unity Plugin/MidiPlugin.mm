#import <CoreAudioKit/CoreAudioKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <CoreMIDI/MIDINetworkSession.h>
#include <mach/mach_time.h>

#import "MidiPlugin.h"

typedef void ( __cdecl *OnMidiNoteOnDelegate )( const char*, int, int, int, int );
typedef void ( __cdecl *OnMidiNoteOffDelegate )( const char*, int, int, int, int );
typedef void ( __cdecl *OnMidiPolyphonicAftertouchDelegate )( const char*, int , int , int , int );
typedef void ( __cdecl *OnMidiControlChangeDelegate )( const char*, int , int , int , int );
typedef void ( __cdecl *OnMidiProgramChangeDelegate )( const char*, int , int , int );
typedef void ( __cdecl *OnMidiChannelAftertouchDelegate )( const char*, int , int , int );
typedef void ( __cdecl *OnMidiPitchWheelDelegate )( const char*, int , int , int );
typedef void ( __cdecl *OnMidiSystemExclusiveDelegate )( const char*, int , unsigned char*, int );
typedef void ( __cdecl *OnMidiTimeCodeQuarterFrameDelegate )( const char*, int , int );
typedef void ( __cdecl *OnMidiSongSelectDelegate )( const char*, int , int );
typedef void ( __cdecl *OnMidiSongPositionPointerDelegate )( const char*, int , int );
typedef void ( __cdecl *OnMidiTuneRequestDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiTimingClockDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiStartDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiContinueDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiStopDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiActiveSensingDelegate )( const char*, int );
typedef void ( __cdecl *OnMidiResetDelegate )( const char*, int );

#ifdef __cplusplus
extern "C" {
#endif
    void midiPluginInitialize();
    void midiPluginTerminate();
    void sendMidiData(const char* deviceId, unsigned char* byteArray, int length);
    void startScanBluetoothMidiDevices();
    void stopScanBluetoothMidiDevices();
    const char* getDeviceName(const char* deviceId);
    void SetMidiNoteOnCallback(OnMidiNoteOnDelegate callback);
    void SetMidiNoteOffCallback(OnMidiNoteOffDelegate callback);
    void SetMidiPolyphonicAftertouchDelegate(OnMidiPolyphonicAftertouchDelegate callback);
    void SetMidiControlChangeDelegate(OnMidiControlChangeDelegate callback);
    void SetMidiProgramChangeDelegate(OnMidiProgramChangeDelegate callback);
    void SetMidiChannelAftertouchDelegate(OnMidiChannelAftertouchDelegate callback);
    void SetMidiPitchWheelDelegate(OnMidiPitchWheelDelegate callback);
    void SetMidiSystemExclusiveDelegate(OnMidiSystemExclusiveDelegate callback);
    void SetMidiTimeCodeQuarterFrameDelegate(OnMidiTimeCodeQuarterFrameDelegate callback);
    void SetMidiSongSelectDelegate(OnMidiSongSelectDelegate callback);
    void SetMidiSongPositionPointerDelegate(OnMidiSongPositionPointerDelegate callback);
    void SetMidiTuneRequestDelegate(OnMidiTuneRequestDelegate callback);
    void SetMidiTimingClockDelegate(OnMidiTimingClockDelegate callback);
    void SetMidiStartDelegate(OnMidiStartDelegate callback);
    void SetMidiContinueDelegate(OnMidiContinueDelegate callback);
    void SetMidiStopDelegate(OnMidiStopDelegate callback);
    void SetMidiActiveSensingDelegate(OnMidiActiveSensingDelegate callback);
    void SetMidiResetDelegate(OnMidiResetDelegate callback);

    extern UIViewController* UnityGetGLViewController();
    extern void UnitySendMessage(const char* obj, const char* method, const char* msg);
#ifdef __cplusplus
}
#endif

@implementation MidiPlugin

static MidiPlugin* instance;

MIDIClientRef midiClient;
MIDIPortRef inputPort;
MIDIPortRef outputPort;
NSHashTable *sourceSet;
NSHashTable *destinationSet;
NSMutableDictionary *sysexMessage;
NSMutableDictionary *packetLists;
NSMutableDictionary *deviceNames;
UINavigationController *navigationController;

OnMidiNoteOnDelegate onMidiNoteOn;
OnMidiNoteOffDelegate onMidiNoteOff;
OnMidiPolyphonicAftertouchDelegate onMidiPolyphonicAftertouch;
OnMidiControlChangeDelegate onMidiControlChange;
OnMidiProgramChangeDelegate onMidiProgramChange;
OnMidiChannelAftertouchDelegate onMidiChannelAftertouch;
OnMidiPitchWheelDelegate onMidiPitchWheel;
OnMidiSystemExclusiveDelegate onMidiSystemExclusive;
OnMidiTimeCodeQuarterFrameDelegate onMidiTimeCodeQuarterFrame;
OnMidiSongSelectDelegate onMidiSongSelect;
OnMidiSongPositionPointerDelegate onMidiSongPositionPointer;
OnMidiTuneRequestDelegate onMidiTuneRequest;
OnMidiTimingClockDelegate onMidiTimingClock;
OnMidiStartDelegate onMidiStart;
OnMidiContinueDelegate onMidiContinue;
OnMidiStopDelegate onMidiStop;
OnMidiActiveSensingDelegate onMidiActiveSensing;
OnMidiResetDelegate onMidiReset;

void midiPluginInitialize() {
    if (instance == nil) {
        instance = [[MidiPlugin alloc] init];
    }

    // network session
    MIDINetworkSession* session = [MIDINetworkSession defaultSession];
    session.enabled = YES;
    session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
    [[NSNotificationCenter defaultCenter] addObserver:instance selector:@selector(getMidiDevices) name:MIDINetworkNotificationContactsDidChange object:nil];
}

void startScanBluetoothMidiDevices() {
#if !TARGET_IPHONE_SIMULATOR
    if (navigationController.presentingViewController != nil) {
        // already showing
        return;
    }
    CABTMIDICentralViewController* centralViewController = [[CABTMIDICentralViewController alloc] init];
    navigationController = [[UINavigationController alloc] initWithRootViewController: centralViewController];
    navigationController.modalPresentationStyle = UIModalPresentationPopover;
    [UnityGetGLViewController() presentViewController:navigationController animated:YES completion:^{
        [instance getMidiDevices];
    }];
#endif
}

void stopScanBluetoothMidiDevices() {
#if !TARGET_IPHONE_SIMULATOR
    if (navigationController) {
        [navigationController dismissViewControllerAnimated: YES completion:^{
            navigationController = nil;
        }];
    }
#endif
}

void midiPluginTerminate() {
    NSUInteger sourceCount = MIDIGetNumberOfSources();
    for (NSUInteger i = 0; i < sourceCount; ++i) {
        MIDIEndpointRef endpoint = MIDIGetSource(i);
        MIDIPortDisconnectSource(inputPort, endpoint);
    }

    MIDIPortDispose(inputPort);
    MIDIPortDispose(outputPort);
    MIDIClientDispose(midiClient);
}

const char* getDeviceName(const char* deviceId) {
    NSNumber* deviceNumber = [NSNumber numberWithInteger: [[NSString stringWithUTF8String: deviceId] intValue]];
    if (deviceNumber == nil || deviceNames[deviceNumber] == nil) {
        return NULL;
    }
    return strdup(((NSString *)deviceNames[deviceNumber]).UTF8String);
}

void SetMidiNoteOnCallback(OnMidiNoteOnDelegate callback) {
    onMidiNoteOn = callback;
}
void SetMidiNoteOffCallback(OnMidiNoteOffDelegate callback) {
    onMidiNoteOff = callback;
}
void SetMidiPolyphonicAftertouchDelegate(OnMidiPolyphonicAftertouchDelegate callback) {
    onMidiPolyphonicAftertouch = callback;
}
void SetMidiControlChangeDelegate(OnMidiControlChangeDelegate callback) {
    onMidiControlChange = callback;
}
void SetMidiProgramChangeDelegate(OnMidiProgramChangeDelegate callback) {
    onMidiProgramChange = callback;
}
void SetMidiChannelAftertouchDelegate(OnMidiChannelAftertouchDelegate callback) {
    onMidiChannelAftertouch = callback;
}
void SetMidiPitchWheelDelegate(OnMidiPitchWheelDelegate callback) {
    onMidiPitchWheel = callback;
}
void SetMidiSystemExclusiveDelegate(OnMidiSystemExclusiveDelegate callback) {
    onMidiSystemExclusive = callback;
}
void SetMidiTimeCodeQuarterFrameDelegate(OnMidiTimeCodeQuarterFrameDelegate callback) {
    onMidiTimeCodeQuarterFrame = callback;
}
void SetMidiSongSelectDelegate(OnMidiSongSelectDelegate callback) {
    onMidiSongSelect = callback;
}
void SetMidiSongPositionPointerDelegate(OnMidiSongPositionPointerDelegate callback) {
    onMidiSongPositionPointer = callback;
}
void SetMidiTuneRequestDelegate(OnMidiTuneRequestDelegate callback) {
    onMidiTuneRequest = callback;
}
void SetMidiTimingClockDelegate(OnMidiTimingClockDelegate callback) {
    onMidiTimingClock = callback;
}
void SetMidiStartDelegate(OnMidiStartDelegate callback) {
    onMidiStart = callback;
}
void SetMidiContinueDelegate(OnMidiContinueDelegate callback) {
    onMidiContinue = callback;
}
void SetMidiStopDelegate(OnMidiStopDelegate callback) {
    onMidiStop = callback;
}
void SetMidiActiveSensingDelegate(OnMidiActiveSensingDelegate callback) {
    onMidiActiveSensing = callback;
}
void SetMidiResetDelegate(OnMidiResetDelegate callback) {
    onMidiReset = callback;
}

void sendMidiData(const char* deviceId, unsigned char* byteArray, int length) {
    ItemCount numOfDevices = MIDIGetNumberOfDevices();
    for (int i = 0; i < numOfDevices; i++) {
        MIDIDeviceRef midiDevice = MIDIGetDevice(i);

        int deviceUniqueId;
        MIDIObjectGetIntegerProperty(midiDevice, kMIDIPropertyUniqueID, &deviceUniqueId);
        NSNumber* deviceNumber = [NSNumber numberWithInt:deviceUniqueId];

        if ([[NSString stringWithFormat:@"%@", deviceNumber] isEqualToString:[NSString stringWithUTF8String:deviceId]]) {
            // send to all destinations
            ItemCount numOfEntities = MIDIDeviceGetNumberOfEntities(midiDevice);
            for (int j = 0; j < numOfEntities; j++) {
                MIDIEntityRef midiEntity = MIDIDeviceGetEntity(midiDevice, j);
                ItemCount numOfDestinations = MIDIEntityGetNumberOfDestinations(midiEntity);
                for (int k = 0; k < numOfDestinations; k++) {
                    MIDIEndpointRef endpoint = MIDIEntityGetDestination(midiEntity, k);

                    int endpointUniqueId;
                    MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
                    NSNumber* endpointNumber = [NSNumber numberWithInt:endpointUniqueId];

                    MIDIPacketList *packetListPtr = (MIDIPacketList *)((NSNumber *)packetLists[endpointNumber]).longValue;
                    if (packetListPtr) {
                        MIDIPacket *packet = MIDIPacketListInit(packetListPtr);
                        packet = MIDIPacketListAdd(packetListPtr, 1024, packet, mach_absolute_time(), length, byteArray);

                        OSStatus err;
                        err = MIDISend(outputPort, endpoint, packetListPtr);
                    }
                }
            }
            break;
        }
    }
}

void midiInputCallback(const MIDIPacketList *list, void *procRef, void *srcRef) {
    MidiPlugin *plugin = (__bridge MidiPlugin*)procRef;
    NSNumber* endpointId = (__bridge NSNumber*)srcRef; // srcRef passed from MIDIPortConnectSource argument

    const MIDIPacket *packet = &list->packet[0]; //gets first packet in list
    for (NSUInteger i = 0; i < list->numPackets; ++i) {
        for (NSUInteger dataIndex = 0; dataIndex < packet->length;) {
            if (sysexMessage[endpointId] != nil) {
                // process sysex until end(0xF7)
                if ((packet->data[dataIndex] & 0x80) == 0x80) {
                    // sysex interrupted
                    [sysexMessage removeObjectForKey: endpointId];
                    continue;
                }
                else {
                    NSMutableArray* sysexArray;
                    NSMutableString* sysex;
                    if (onMidiSystemExclusive) {
                        sysexArray = sysexMessage[endpointId];
                    } else {
                        sysex = sysexMessage[endpointId];
                    }
                    if (onMidiSystemExclusive) {
                        [sysexArray addObject: [NSNumber numberWithInt:packet->data[dataIndex]]];
                    } else {
                        [sysex appendString: @","];
                        [sysex appendString: [NSString stringWithFormat:@"%d", packet->data[dataIndex]]];
                    }
                    if (packet->data[dataIndex] == 0xF7) {
                        // sysex finished
                        if (onMidiSystemExclusive) {
                            unsigned char* sysexData = unsigned char[[sysexArray count]];
                            for (int i = 0; i < [sysexArray count]; i++) {
                                sysexData[i] = ((NSNumber *)[sysexArray objectAtIndex: i]).unsignedCharValue;
                            }
                            onMidiSystemExclusive([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, sysexData, [sysexArray count]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiSystemExclusive", sysex.UTF8String);
                        }
                        [sysexMessage removeObjectForKey: endpointId];
                        dataIndex++;
                        continue;
                    }
                }
                dataIndex++;
            } else {
                // process channel messages
                int status = packet->data[dataIndex];
                switch (status & 0xf0) {
                    case 0x80:
                        if (dataIndex + 2 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiNoteOff) {
                            onMidiNoteOff([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiNoteOff", [NSString stringWithFormat:@"%@,0,%d,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]].UTF8String);
                        }
                        dataIndex += 3;
                        break;
                    case 0x90:
                        if (dataIndex + 2 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (packet->data[dataIndex + 2] == 0) {
                            if (onMidiNoteOff) {
                                onMidiNoteOff([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]);
                            } else {
                                UnitySendMessage(GAME_OBJECT_NAME, "OnMidiNoteOff", [NSString stringWithFormat:@"%@,0,%d,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]].UTF8String);
                            }
                        } else {
                            if (onMidiNoteOn) {
                                onMidiNoteOn([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]);
                            } else {
                                UnitySendMessage(GAME_OBJECT_NAME, "OnMidiNoteOn", [NSString stringWithFormat:@"%@,0,%d,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]].UTF8String);
                            }
                        }
                        dataIndex += 3;
                        break;
                    case 0xa0:
                        if (dataIndex + 2 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiPolyphonicAftertouch) {
                            onMidiPolyphonicAftertouch([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiPolyphonicAftertouch", [NSString stringWithFormat:@"%@,0,%d,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]].UTF8String);
                        }
                        dataIndex += 3;
                        break;
                    case 0xb0:
                        if (dataIndex + 2 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiControlChange) {
                            onMidiControlChange([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiControlChange", [NSString stringWithFormat:@"%@,0,%d,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1], packet->data[dataIndex + 2]].UTF8String);
                        }
                        dataIndex += 3;
                        break;
                    case 0xc0:
                        if (dataIndex + 1 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiProgramChange) {
                            onMidiProgramChange([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiProgramChange", [NSString stringWithFormat:@"%@,0,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1]].UTF8String);
                        }
                        dataIndex += 2;
                        break;
                    case 0xd0:
                        if (dataIndex + 1 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiChannelAftertouch) {
                            onMidiChannelAftertouch([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1]);
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "onMidiChannelAftertouch", [NSString stringWithFormat:@"%@,0,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1]].UTF8String);
                        }
                        dataIndex += 2;
                        break;
                    case 0xe0:
                        if (dataIndex + 2 >= packet->length) {
                            // invalid data
                            dataIndex = packet->length;
                            break;
                        }
                        if (onMidiPitchWheel) {
                            onMidiPitchWheel([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1] | (packet->data[dataIndex + 2] << 7));
                        } else {
                            UnitySendMessage(GAME_OBJECT_NAME, "OnMidiPitchWheel", [NSString stringWithFormat:@"%@,0,%d,%d", endpointId, packet->data[dataIndex + 0] & 0x0f, packet->data[dataIndex + 1] | (packet->data[dataIndex + 2] << 7)].UTF8String);
                        }
                        dataIndex += 3;
                        break;
                    case 0xf0:
                        switch (status) {
                            case 0xf0: {
                                    // start with F0, ends with F7, or stops with > 0x80
                                    NSMutableArray* sysexArray;
                                    NSMutableString* sysex;
                                    if (sysexMessage[endpointId] == nil) {
                                        if (onMidiSystemExclusive) {
                                            sysexArray = [[NSMutableArray alloc] init];
                                        } else {
                                            sysex = [[NSMutableString alloc] init];
                                        }
                                        sysexMessage[endpointId] = sysex;
                                        if (!onMidiSystemExclusive) {
                                            [sysex appendString: [NSString stringWithFormat:@"%@,0", endpointId]]; // groupId: always 0
                                        }
                                    } else {
                                        if (onMidiSystemExclusive) {
                                            sysexArray = sysexMessage[endpointId];
                                        } else {
                                            sysex = sysexMessage[endpointId];
                                        }
                                    }
                                    if (onMidiSystemExclusive) {
                                        [sysexArray addObject: [NSNumber numberWithInt:packet->data[dataIndex]]];
                                    } else {
                                        [sysex appendString: @","];
                                        [sysex appendString: [NSString stringWithFormat:@"%d", packet->data[dataIndex]]];
                                    }
                                    dataIndex++;
                                    // process until end of packet data
                                    for (;dataIndex < packet->length;) {
                                        if ((packet->data[dataIndex] & 0x80) == 0x80) {
                                            // sysex interrupted
                                            [sysexMessage removeObjectForKey: endpointId];
                                            // parse again: don't increment dataIndex
                                            break;
                                        } else {
                                            NSMutableArray* sysexArray;
                                            NSMutableString* sysex;
                                            if (onMidiSystemExclusive) {
                                                sysexArray = sysexMessage[endpointId];
                                                [sysexArray addObject: [NSNumber numberWithInt:packet->data[dataIndex]]];
                                            } else {
                                                sysex = sysexMessage[endpointId];
                                                [sysex appendString: @","];
                                                [sysex appendString: [NSString stringWithFormat:@"%d", packet->data[dataIndex]]];
                                            }
                                            if (packet->data[dataIndex] == 0xF7) {
                                                // sysex finished
                                                if (onMidiSystemExclusive) {
                                                    unsigned char* sysexData = unsigned char[[sysexArray count]];
                                                    for (int i = 0; i < [sysexArray count]; i++) {
                                                        sysexData[i] = ((NSNumber *)[sysexArray objectAtIndex: i]).unsignedCharValue;
                                                    }
                                                    onMidiSystemExclusive([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, sysexData, [sysexArray count]);
                                                } else {
                                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiSystemExclusive", sysex.UTF8String);
                                                }
                                                [sysexMessage removeObjectForKey: endpointId];
                                                dataIndex++;
                                                break;
                                            }
                                        }
                                        dataIndex++;
                                    }
                                }
                                break;
                            case 0xf1:
                                if (dataIndex + 1 >= packet->length) {
                                    // invalid data
                                    dataIndex = packet->length;
                                    break;
                                }
                                if (onMidiTimeCodeQuarterFrame) {
                                    onMidiTimeCodeQuarterFrame([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 1] & 0x7f);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiTimeCodeQuarterFrame", [NSString stringWithFormat:@"%@,0,%d", endpointId, packet->data[dataIndex + 1] & 0x7f].UTF8String);
                                }
                                dataIndex += 2;
                                break;
                            case 0xf2:
                                if (dataIndex + 2 >= packet->length) {
                                    // invalid data
                                    dataIndex = packet->length;
                                    break;
                                }
                                if (onMidiSongPositionPointer) {
                                    onMidiSongPositionPointer([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 1] | (packet->data[dataIndex + 2] << 7));
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiSongPositionPointer", [NSString stringWithFormat:@"%@,0,%d", endpointId, packet->data[dataIndex + 1] | (packet->data[dataIndex + 2] << 7)].UTF8String);
                                }
                                dataIndex += 3;
                                break;
                            case 0xf3:
                                if (dataIndex + 1 >= packet->length) {
                                    // invalid data
                                    dataIndex = packet->length;
                                    break;
                                }
                                if (onMidiSongSelect) {
                                    onMidiSongSelect([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, packet->data[dataIndex + 1] & 0x7f);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiSongSelect", [NSString stringWithFormat:@"%@,0,%d", endpointId, packet->data[dataIndex + 1] & 0x7f].UTF8String);
                                }
                                dataIndex += 2;
                                break;
                            case 0xf4:
                                // undefined
                                dataIndex++;
                                break;
                            case 0xf5:
                                // undefined
                                dataIndex++;
                                break;
                            case 0xf6:
                                if (onMidiTuneRequest) {
                                    onMidiTuneRequest([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiTuneRequest", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xf7:
                                // sysex end: don't come with single data, ignored
                                dataIndex++;
                                break;
                            case 0xf8:
                                if (onMidiTimingClock) {
                                    onMidiTimingClock([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiTimingClock", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xf9:
                                // undefined
                                dataIndex++;
                                break;
                            case 0xfa:
                                if (onMidiStart) {
                                    onMidiStart([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiStart", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xfb:
                                if (onMidiContinue) {
                                    onMidiContinue([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiContinue", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xfc:
                                if (onMidiStop) {
                                    onMidiStop([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiStop", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xfd:
                                // undefined
                                dataIndex++;
                                break;
                            case 0xfe:
                                if (onMidiActiveSensing) {
                                    onMidiActiveSensing([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiActiveSensing", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                            case 0xff:
                                if (onMidiReset) {
                                    onMidiReset([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0);
                                } else {
                                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiReset", [NSString stringWithFormat:@"%@,0", endpointId].UTF8String);
                                }
                                dataIndex++;
                                break;
                        }
                        break;
                    default:
                        // 0x00 - 0x7f: invalid data, ingored
                        dataIndex++;
                        break;
                }// switch
            }// if
        }// for (NSUInteger dataIndex = 0; dataIndex < packet->length;) {
        packet = MIDIPacketNext(packet);
    }// for (NSUInteger i = 0; i < list->numPackets; ++i) {
}

- (id) init {
    if (self = [super init]) {
        sourceSet = [[NSHashTable alloc] init];
        destinationSet = [[NSHashTable alloc] init];
        sysexMessage = [[NSMutableDictionary alloc] init];
        packetLists = [[NSMutableDictionary alloc] init];
        deviceNames = [[NSMutableDictionary alloc] init];

        MIDIClientCreate(CFSTR("MidiPlugin"), NULL, NULL, &midiClient);
        MIDIInputPortCreate(midiClient, CFSTR("Input"), midiInputCallback, (__bridge_retained void *)self, &inputPort);
        MIDIOutputPortCreate(midiClient, CFSTR("Output"), &outputPort);
    }

    return self;
}

- (void) getMidiDevices {
    ItemCount numOfDevices = MIDIGetNumberOfDevices();
    for (int i = 0; i < numOfDevices; i++) {
        MIDIDeviceRef midiDevice = MIDIGetDevice(i);

        CFStringRef deviceName; 
        MIDIObjectGetStringProperty(midiDevice, kMIDIPropertyName, &deviceName);

        int deviceUniqueId;
        MIDIObjectGetIntegerProperty(midiDevice, kMIDIPropertyUniqueID, &deviceUniqueId);
        NSNumber* deviceNumber = [NSNumber numberWithInt:deviceUniqueId];

        if (deviceNames[deviceNumber] == nil) {
            deviceNames[deviceNumber] = (__bridge NSString *)deviceName;
        }

        ItemCount numOfEntities = MIDIDeviceGetNumberOfEntities(midiDevice);
        for (int j = 0; j < numOfEntities; j++) {
            MIDIEntityRef midiEntity = MIDIDeviceGetEntity(midiDevice, j);

            // source
            ItemCount numOfSources = MIDIEntityGetNumberOfSources(midiEntity);
            for (int k = 0; k < numOfSources; k++) {
                MIDIEndpointRef endpoint = MIDIEntityGetSource(midiEntity, k);

                int endpointUniqueId;
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
                NSNumber* endpointNumber = [NSNumber numberWithInt:endpointUniqueId];
                if (![sourceSet member: endpointNumber]) {
                    OSStatus err;
                    err = MIDIPortConnectSource(inputPort, endpoint, (__bridge void*)endpointNumber);
                    if (err == noErr) {
                        [sourceSet addObject: endpointNumber];

                    }
                }
            }
            if (numOfSources > 0) {
                UnitySendMessage(GAME_OBJECT_NAME, "OnMidiInputDeviceAttached", [NSString stringWithFormat:@"%@", deviceNumber].UTF8String);
            }

            // destination
            ItemCount numOfDestinations = MIDIEntityGetNumberOfDestinations(midiEntity);
            for (int k = 0; k < numOfDestinations; k++) {
                MIDIEndpointRef endpoint = MIDIEntityGetDestination(midiEntity, k);

                int endpointUniqueId;
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
                NSNumber* endpointNumber = [NSNumber numberWithInt:endpointUniqueId];
                if (![destinationSet member: endpointNumber]) {
                    [destinationSet addObject: endpointNumber];

                    if (packetLists[endpointNumber] == nil) {
                        Byte *packetBuffer = new Byte[1024];
                        MIDIPacketList *packetListPtr = (MIDIPacketList *)packetBuffer;
                        packetLists[endpointNumber] = [NSNumber numberWithLong:(long)packetListPtr];
                    }

                }
            }
            if (numOfDestinations > 0) {
                UnitySendMessage(GAME_OBJECT_NAME, "OnMidiOutputDeviceAttached", [NSString stringWithFormat:@"%@", deviceNumber].UTF8String);
            }
        }
    }
}

@end
