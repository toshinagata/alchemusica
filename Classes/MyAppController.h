//
//  MyAppController.h
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

extern NSString *MyAppControllerMIDISetupDidChangeNotification;
extern NSString *MyAppControllerModalPanelTimerNotification;

@class MyDocument;
@interface MyAppController : NSObject
{
	IBOutlet NSMenu *scriptMenu;
	NSMutableArray *scriptMenuInfos;
	id rubyProgressPanelController;
}
- (void)updateScriptMenu: (NSNotification *)aNotification;
- (void)registerScriptMenu: (NSString *)commandName withTitle: (NSString *)menuTitle validator:(int32_t)rubyValue;
- (void)performScriptCommand: (NSString *)command forDocument: (MyDocument *)document;
- (void)doScriptCommand: (id)sender;
- (IBAction)openAudioSettingsPanel: (id)sender;
- (IBAction)openMetronomeSettingsPanel: (id)sender;
- (IBAction)openAboutWindow:(id)sender;
- (IBAction)updateAudioAndMIDISettings:(id)sender;
- (id)documentAtIndex: (int)idx;

- (void)getRubyVersion:(NSString **)outVersion copyright:(NSString **)outCopyright;
- (void)getVersion:(NSString **)outVersion copyright:(NSString **)outCopyright lastBuild:(NSString **)outLastBuild revision:(int *)outRevision;

- (int)getOSXVersion;

@end

extern id MyAppCallback_getObjectGlobalSettings(id keyPath);
extern void MyAppCallback_setObjectGlobalSettings(id keyPath, id value);
extern void MyAppCallback_saveGlobalSettings(void);
