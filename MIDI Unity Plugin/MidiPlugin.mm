#import <CoreAudioKit/CoreAudioKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <CoreMIDI/MIDINetworkSession.h>
#include <mach/mach_time.h>

#import "MidiPlugin.h"

typedef void ( __cdecl *OnMidiInputDeviceAttachedDelegate )( const char* );
typedef void ( __cdecl *OnMidiOutputDeviceAttachedDelegate )( const char* );
typedef void ( __cdecl *OnMidiInputDeviceDetachedDelegate )( const char* );
typedef void ( __cdecl *OnMidiOutputDeviceDetachedDelegate )( const char* );

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

    void SetMidiInputDeviceAttachedCallback(OnMidiInputDeviceAttachedDelegate callback);
    void SetMidiOutputDeviceAttachedCallback(OnMidiOutputDeviceAttachedDelegate callback);
    void SetMidiInputDeviceDetachedCallback(OnMidiInputDeviceDetachedDelegate callback);
    void SetMidiOutputDeviceDetachedCallback(OnMidiOutputDeviceDetachedDelegate callback);

    void sendMidiData(const char* deviceId, unsigned char* byteArray, int length);
    void startScanBluetoothMidiDevices();
    void stopScanBluetoothMidiDevices();
    const char* getDeviceName(const char* deviceId);
    const char* getVendorId(const char* deviceId);
    const char* getProductId(const char* deviceId);
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
NSMutableDictionary *vendorNames;
NSMutableDictionary *productNames;
UINavigationController *navigationController;

NSTimer *deviceUpdateTimer;

OnMidiInputDeviceAttachedDelegate onMidiInputDeviceAttached;
OnMidiOutputDeviceAttachedDelegate onMidiOutputDeviceAttached;
OnMidiInputDeviceDetachedDelegate onMidiInputDeviceDetached;
OnMidiOutputDeviceDetachedDelegate onMidiOutputDeviceDetached;

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

    deviceUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:instance selector:@selector(getMidiDevices) userInfo:nil repeats:YES];
    [deviceUpdateTimer fire];

    // network session
    MIDINetworkSession* session = [MIDINetworkSession defaultSession];
    session.enabled = YES;
    session.connectionPolicy = MIDINetworkConnectionPolicy_Anyone;
    [[NSNotificationCenter defaultCenter] addObserver:instance selector:@selector(getMidiDevices) name:MIDINetworkNotificationContactsDidChange object:nil];
}

#if !TARGET_IPHONE_SIMULATOR
- (void)closeBluetoothMidiDevices:(id)sender {
    [navigationController dismissViewControllerAnimated:YES completion:nil];
}
#endif

void startScanBluetoothMidiDevices() {
#if !TARGET_IPHONE_SIMULATOR
    if (navigationController.presentingViewController != nil) {
        // already showing
        return;
    }
    CABTMIDICentralViewController* centralViewController = [[CABTMIDICentralViewController alloc] init];
    navigationController = [[UINavigationController alloc] initWithRootViewController: centralViewController];
    navigationController.modalPresentationStyle = UIModalPresentationPopover;
    UIViewController* unityViewController = UnityGetGLViewController();
    navigationController.popoverPresentationController.sourceView = unityViewController.view;
    navigationController.popoverPresentationController.sourceRect = CGRectMake(unityViewController.view.bounds.size.width / 2.0, unityViewController.view.bounds.size.height, 0.0, 0.0);

    // Add 'done' button to the navigation bar
    // https://developer.apple.com/forums/thread/31822?answerId=195499022#195499022
    centralViewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:instance action:@selector(closeBluetoothMidiDevices:)];

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
    [deviceUpdateTimer invalidate];

    NSUInteger sourceCount = MIDIGetNumberOfSources();
    for (NSUInteger i = 0; i < sourceCount; ++i) {
        MIDIEndpointRef endpoint = MIDIGetSource(i);
        MIDIPortDisconnectSource(inputPort, endpoint);
    }

    MIDIPortDispose(inputPort);
    MIDIPortDispose(outputPort);
    MIDIClientDispose(midiClient);
    instance = nil;
}

const char* getDeviceName(const char* deviceId) {
    NSNumber* deviceNumber = [NSNumber numberWithInteger: [[NSString stringWithUTF8String: deviceId] intValue]];
    if (deviceNumber == nil) {
        return NULL;
    }
    for (id key in deviceNames) {
        if (deviceNumber.intValue == ((NSNumber*)key).intValue) {
            return strdup(((NSString *)deviceNames[key]).UTF8String);
        }
    }
    return NULL;
}

const char* getVendorId(const char* deviceId) {
    NSNumber* deviceNumber = [NSNumber numberWithInteger: [[NSString stringWithUTF8String: deviceId] intValue]];
    if (deviceNumber == nil) {
        return NULL;
    }
    for (id key in vendorNames) {
        if (deviceNumber.intValue == ((NSNumber*)key).intValue) {
            return strdup(((NSString *)vendorNames[key]).UTF8String);
        }
    }
    return NULL;
}

const char* getProductId(const char* deviceId) {
    NSNumber* deviceNumber = [NSNumber numberWithInteger: [[NSString stringWithUTF8String: deviceId] intValue]];
    if (deviceNumber == nil) {
        return NULL;
    }
    for (id key in productNames) {
        if (deviceNumber.intValue == ((NSNumber*)key).intValue) {
            return strdup(((NSString *)productNames[key]).UTF8String);
        }
    }
    return NULL;
}

void SetMidiInputDeviceAttachedCallback(OnMidiInputDeviceAttachedDelegate callback) {
    onMidiInputDeviceAttached = callback;
}
void SetMidiOutputDeviceAttachedCallback(OnMidiOutputDeviceAttachedDelegate callback) {
    onMidiOutputDeviceAttached = callback;
}
void SetMidiInputDeviceDetachedCallback(OnMidiInputDeviceDetachedDelegate callback) {
    onMidiInputDeviceDetached = callback;
}
void SetMidiOutputDeviceDetachedCallback(OnMidiOutputDeviceDetachedDelegate callback) {
    onMidiOutputDeviceDetached = callback;
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
    BOOL deviceFound = NO;

    // First, try to find and send to the device through entities (for physical devices)
    for (ItemCount i = 0; i < numOfDevices && !deviceFound; i++) {
        MIDIDeviceRef midiDevice = MIDIGetDevice(i);
        ItemCount numOfEntities = MIDIDeviceGetNumberOfEntities(midiDevice);
        
        for (ItemCount j = 0; j < numOfEntities; j++) {
            MIDIEntityRef midiEntity = MIDIDeviceGetEntity(midiDevice, j);
            ItemCount numOfDestinations = MIDIEntityGetNumberOfDestinations(midiEntity);
            
            for (ItemCount k = 0; k < numOfDestinations; k++) {
                MIDIEndpointRef endpoint = MIDIEntityGetDestination(midiEntity, k);
                
                SInt32 endpointUniqueId;
                MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
                NSString* endpointUniqueIdStr = [NSString stringWithFormat:@"%d", endpointUniqueId];
                
                if ([endpointUniqueIdStr isEqualToString:[NSString stringWithUTF8String:deviceId]]) {
                    deviceFound = YES;
                    sendMidiPacketToDevice(endpoint, byteArray, length);
                    break;
                }
            }
        }
    }

    // If the device wasn't found and it might be a virtual device, check destinations directly
    if (!deviceFound) {
        ItemCount numOfDestinations = MIDIGetNumberOfDestinations();
        for (ItemCount i = 0; i < numOfDestinations; i++) {
            MIDIEndpointRef endpoint = MIDIGetDestination(i);
            
            SInt32 endpointUniqueId;
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
            NSString* endpointUniqueIdStr = [NSString stringWithFormat:@"%d", endpointUniqueId];
            
            if ([endpointUniqueIdStr isEqualToString:[NSString stringWithUTF8String:deviceId]]) {
                sendMidiPacketToDevice(endpoint, byteArray, length);
                break;
            }
        }
    }
}

void sendMidiPacketToDevice(MIDIEndpointRef endpoint, unsigned char* byteArray, int length) {
    MIDIPacketList packetList;
    MIDIPacket* packet = MIDIPacketListInit(&packetList);
    packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, mach_absolute_time(), length, byteArray);
    
    if (packet) {
        OSStatus err = MIDISend(outputPort, endpoint, &packetList);
        if (err != noErr) {
            // Handle the error
            NSLog(@"Error sending MIDI data: %d", (int)err);
        }
    }
}

void midiInputCallback(const MIDIPacketList *list, void *procRef, void *srcRef) {
//    MidiPlugin *plugin = (__bridge MidiPlugin*)procRef;
    NSNumber* endpointId = (__bridge NSNumber*)srcRef; // srcRef passed from MIDIPortConnectSource argument

    const MIDIPacket *packet = &list->packet[0]; //gets first packet in list
    for (NSUInteger i = 0; i < list->numPackets; ++i) {
        for (NSUInteger dataIndex = 0; dataIndex < packet->length;) {
            if (sysexMessage[endpointId] != nil) {
                // process sysex until end(0xF7)
                if (packet->data[dataIndex] != 0xF7 && (packet->data[dataIndex] & 0x80) == 0x80) {
                    // sysex interrupted
                    [sysexMessage removeObjectForKey: endpointId];
                    continue;
                } else {
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
                            unsigned char* sysexData = new unsigned char[[sysexArray count]];
                            for (int i = 0; i < [sysexArray count]; i++) {
                                sysexData[i] = ((NSNumber *)[sysexArray objectAtIndex: i]).unsignedCharValue;
                            }
                            onMidiSystemExclusive([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, sysexData, (int)[sysexArray count]);
                            delete[] sysexData;
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
                                            sysexMessage[endpointId] = sysexArray;
                                        } else {
                                            sysex = [[NSMutableString alloc] init];
                                            sysexMessage[endpointId] = sysex;
                                        }
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
                                    // add F0
                                    if (onMidiSystemExclusive) {
                                        [sysexArray addObject: [NSNumber numberWithInt:packet->data[dataIndex]]];
                                    } else {
                                        [sysex appendString: @","];
                                        [sysex appendString: [NSString stringWithFormat:@"%d", packet->data[dataIndex]]];
                                    }
                                    dataIndex++;
                                    continue;
                                }
                                break;
                            case 0xf7: {
                                    NSMutableArray* sysexArray;
                                    NSMutableString* sysex;
                                    if (sysexMessage[endpointId] == nil) {
                                        if (onMidiSystemExclusive) {
                                            sysexArray = [[NSMutableArray alloc] init];
                                            sysexMessage[endpointId] = sysexArray;
                                        } else {
                                            sysex = [[NSMutableString alloc] init];
                                            sysexMessage[endpointId] = sysex;
                                        }
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
                                    // add F7
                                    if (onMidiSystemExclusive) {
                                        [sysexArray addObject: [NSNumber numberWithInt:packet->data[dataIndex]]];
                                    } else {
                                        [sysex appendString: @","];
                                        [sysex appendString: [NSString stringWithFormat:@"%d", packet->data[dataIndex]]];
                                    }
                                    dataIndex++;
                                    // sysex finished
                                    if (onMidiSystemExclusive) {
                                        unsigned char* sysexData = new unsigned char[[sysexArray count]];
                                        for (int i = 0; i < [sysexArray count]; i++) {
                                            sysexData[i] = ((NSNumber *)[sysexArray objectAtIndex: i]).unsignedCharValue;
                                        }
                                        onMidiSystemExclusive([NSString stringWithFormat:@"%@", endpointId].UTF8String, 0, sysexData, (int)[sysexArray count]);
                                         delete[] sysexData;
                                    } else {
                                        UnitySendMessage(GAME_OBJECT_NAME, "OnMidiSystemExclusive", sysex.UTF8String);
                                    }
                                    [sysexMessage removeObjectForKey: endpointId];
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
        vendorNames = [[NSMutableDictionary alloc] init];
        productNames = [[NSMutableDictionary alloc] init];

        MIDIClientCreate(CFSTR("MidiPlugin"), NULL, NULL, &midiClient);
        MIDIInputPortCreate(midiClient, CFSTR("Input"), midiInputCallback, (__bridge_retained void *)self, &inputPort);
        MIDIOutputPortCreate(midiClient, CFSTR("Output"), &outputPort);
    }

    return self;
}

- (void) getMidiDevices {
    NSDictionary* previousDeviceNames = [deviceNames copy];
    [deviceNames removeAllObjects];

    // source
    ItemCount numOfSources = MIDIGetNumberOfSources();
    for (int k = 0; k < numOfSources; k++) {
        MIDIEndpointRef endpoint = MIDIGetSource(k);

        int endpointUniqueId;
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
        NSNumber* endpointNumber = [NSNumber numberWithInt:endpointUniqueId];

        CFStringRef deviceName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &deviceName);
        deviceNames[endpointNumber] = (__bridge NSString *)deviceName;

        CFStringRef vendorName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &vendorName);
        vendorNames[endpointNumber] = (__bridge NSString *)vendorName;

        CFStringRef productName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyModel, &productName);
        productNames[endpointNumber] = (__bridge NSString *)productName;

        if (![sourceSet member: endpointNumber]) {
            OSStatus err;
            err = MIDIPortConnectSource(inputPort, endpoint, (__bridge void*)endpointNumber);
            if (err == noErr) {
                [sourceSet addObject: endpointNumber];

                BOOL hasKey = NO;
                for (id key in previousDeviceNames) {
                    if (endpointUniqueId == ((NSNumber*)key).intValue) {
                        hasKey = YES;
                        break;
                    }
                }
                if (!hasKey) {
                    if (onMidiInputDeviceAttached) {
                        onMidiInputDeviceAttached([NSString stringWithFormat:@"%@", endpointNumber].UTF8String);
                    } else {
                        UnitySendMessage(GAME_OBJECT_NAME, "OnMidiInputDeviceAttached", [NSString stringWithFormat:@"%@", endpointNumber].UTF8String);
                    }
                }
            }
        }
    }

    // destination
    ItemCount numOfDestinations = MIDIGetNumberOfDestinations();
    for (int k = 0; k < numOfDestinations; k++) {
        MIDIEndpointRef endpoint = MIDIGetDestination(k);

        int endpointUniqueId;
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueId);
        NSNumber* endpointNumber = [NSNumber numberWithInt:endpointUniqueId];

        CFStringRef deviceName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &deviceName);
        deviceNames[endpointNumber] = (__bridge NSString *)deviceName;

        CFStringRef vendorName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &vendorName);
        vendorNames[endpointNumber] = (__bridge NSString *)vendorName;

        CFStringRef productName;
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyModel, &productName);
        productNames[endpointNumber] = (__bridge NSString *)productName;

        if (![destinationSet member: endpointNumber]) {
            [destinationSet addObject: endpointNumber];

            if (packetLists[endpointNumber] == nil) {
                Byte *packetBuffer = new Byte[1024];
                MIDIPacketList *packetListPtr = (MIDIPacketList *)packetBuffer;
                packetLists[endpointNumber] = [NSNumber numberWithLong:(long)packetListPtr];
            }

            BOOL hasKey = NO;
            for (id key in previousDeviceNames) {
                if (endpointUniqueId == ((NSNumber*)key).intValue) {
                    hasKey = YES;
                    break;
                }
            }
            if (!hasKey) {
                if (onMidiOutputDeviceAttached) {
                    onMidiOutputDeviceAttached([NSString stringWithFormat:@"%@", endpointNumber].UTF8String);
                } else {
                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiOutputDeviceAttached", [NSString stringWithFormat:@"%@", endpointNumber].UTF8String);
                }
            }
        }
    }

    for (id key in previousDeviceNames) {
        BOOL hasKey = NO;
        for (id key2 in deviceNames) {
            if (((NSNumber*)key).intValue == ((NSNumber*)key2).intValue) {
                hasKey = YES;
                break;
            }
        }

        if (!hasKey) {
            if ([sourceSet member: key]) {
                [sourceSet removeObject: key];
                if (onMidiInputDeviceDetached) {
                    onMidiInputDeviceDetached([NSString stringWithFormat:@"%@", key].UTF8String);
                } else {
                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiInputDeviceDetached", [NSString stringWithFormat:@"%@", key].UTF8String);
                }
            }
            if ([destinationSet member: key]) {
                [destinationSet removeObject: key];
                if (onMidiOutputDeviceDetached) {
                    onMidiOutputDeviceDetached([NSString stringWithFormat:@"%@", key].UTF8String);
                } else {
                    UnitySendMessage(GAME_OBJECT_NAME, "OnMidiOutputDeviceDetached", [NSString stringWithFormat:@"%@", key].UTF8String);
                }
            }
        }
    }
}

@end
