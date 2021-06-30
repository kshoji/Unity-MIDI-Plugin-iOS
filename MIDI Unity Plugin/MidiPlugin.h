//
//  MIdiPlugin.h
//  Unity-iPhone
//
//  Created by kshoji on 2021/05/06.
//

#ifndef MIdiPlugin_h
#define MIdiPlugin_h

const char *GAME_OBJECT_NAME = "MidiManager";

@interface MidiPlugin : NSObject

- (void) getMidiDevices;

@end

#endif /* MIdiPlugin_h */
