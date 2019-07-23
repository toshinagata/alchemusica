//
//  AudioSettingsPrefPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 2019/07/21.
//  Copyright 2010-2019 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "AudioSettingsPrefPanelController.h"
#import "MyAppController.h"
#import "MDHeaders.h"

@implementation AudioSettingsPrefPanelController

static AudioSettingsPrefPanelController *sharedAudioSettingsPrefPanelController;
static NSString *sPrefKey = @"audioSettingsExportPref";
static NSString *sTypeKey = @"deviceType";
static NSString *sInternalKey = @"saveInternal";
static NSString *sApplicationKey = @"callApplication";
static NSString *sAppPathKey = @"applicationPath";

+ (void)openAudioSettingsPrefPanel
{
	if (sharedAudioSettingsPrefPanelController == nil) {
		sharedAudioSettingsPrefPanelController = [[AudioSettingsPrefPanelController alloc] initWithWindowNibName: @"AudioSettingsPrefPanel"];
	}
	[[sharedAudioSettingsPrefPanelController window] makeKeyAndOrderFront: nil];
	[sharedAudioSettingsPrefPanelController updateDisplay];
}

+ (AudioSettingsPrefPanelController *)sharedAudioSettingsPrefPanelController
{
    if (sharedAudioSettingsPrefPanelController == nil)
        [AudioSettingsPrefPanelController openAudioSettingsPrefPanel];
    return sharedAudioSettingsPrefPanelController;
}

+ (id)lookupDeviceName:(const char *)devname create:(BOOL)flag type:(int)type
{
    int i, j, n;
    id set;
    if (sharedAudioSettingsPrefPanelController != nil && sharedAudioSettingsPrefPanelController->settings != nil) {
        set = sharedAudioSettingsPrefPanelController->settings;
    } else {
        set = MyAppCallback_getObjectGlobalSettings(sPrefKey);
        flag = NO;
    }
    n = (int)[set count];
    for (i = n - 1; i >= 0; i--) {
        NSDictionary *dic = [set objectAtIndex:i];
        NSString *nstr = [dic valueForKey:@"name"];
        if (nstr != nil && strcmp([nstr UTF8String], devname) == 0)
            break;
    }
    if (i < 0 && flag) {
        NSMutableDictionary *mdic = [NSMutableDictionary dictionary];
        [mdic setValue:[NSString stringWithUTF8String:devname] forKey:@"name"];
        [mdic setValue:[NSNumber numberWithInt:type] forKey:sTypeKey];
        [mdic setValue:[NSNumber numberWithInt:0] forKey:sInternalKey];
        //  Look up where to insert
        for (j = 0; j < n; j++) {
            int type0 = [[[set objectAtIndex:j] objectForKey:@"name"] intValue];
            if (type0 > type)
                break;
        }
        [set insertObject:mdic atIndex:j];
        i = j;
    }
    if (i < 0)
        return nil;
    else return [set objectAtIndex: i];
}

+ (BOOL)shouldSaveInternalForDeviceName:(const char *)name
{
    NSDictionary *dic = [AudioSettingsPrefPanelController lookupDeviceName:name create:NO type:0];
    if (dic != nil) {
        return [[dic valueForKey:sInternalKey] intValue] != 0;
    } else return NO;
}

+ (NSString *)shouldCallApplicationForDeviceName:(const char *)name
{
    NSDictionary *dic = [AudioSettingsPrefPanelController lookupDeviceName:name create:NO type:0];
    if (dic != nil) {
        if ([[dic valueForKey:sApplicationKey] intValue] != 0) {
            NSString *s = [dic valueForKey:sAppPathKey];
            return s;
        }
    }
    return nil;
}

- (void)updateDisplay
{
    int i, n, type;
    MDAudioDeviceInfo *ap;
    MDAudioMusicDeviceInfo *mp;
    if (settings == nil) {
        //  Rebuild the settings from the global preference
        NSArray *set = MyAppCallback_getObjectGlobalSettings(sPrefKey);
        settings = [[NSMutableArray array] retain];
        if (set != nil) {
            n = (int)[set count];
            for (i = 0; i < n; i++) {
                NSDictionary *dic = [set objectAtIndex:i];
                [settings addObject:[NSMutableDictionary dictionaryWithDictionary:dic]];
            }
        }
        //  Add entries if the currently active devices are not listed in the settings
        for (i = 0; (ap = MDAudioDeviceInfoAtIndex(i, 0)) != NULL; i++) {
            [[self class] lookupDeviceName:ap->name create:YES type:0];
        }
        for (i = 0; (ap = MDAudioDeviceInfoAtIndex(i, 1)) != NULL; i++) {
            [[self class] lookupDeviceName:ap->name create:YES type:1];
        }
        for (i = 0; (mp = MDAudioMusicDeviceInfoAtIndex(i)) != NULL; i++) {
            [[self class] lookupDeviceName:mp->name create:YES type:2];
        }
        n = (int)[settings count];
        [devicePopUp removeAllItems];
        type = 0;
        for (i = 0; i < n; i++) {
            int type0;
            NSDictionary *dic = [settings objectAtIndex:i];
            type0 = [[dic objectForKey:sTypeKey] intValue];
            if (type != type0) {
                type = type0;
                [[devicePopUp menu] addItem:[NSMenuItem separatorItem]];
            }
            [devicePopUp addItemWithTitle:[dic valueForKey:@"name"]];
            [[devicePopUp lastItem] setTag:i];
        }
    }
    i = (int)[devicePopUp selectedTag];
    if (i < 0) {
        [internalCheck setEnabled:NO];
        [applicationCheck setEnabled:NO];
        [selectButton setEnabled:NO];
        [applicationPath setEnabled:NO];
    } else {
        NSDictionary *dic = [settings objectAtIndex:i];
        NSString *s;
        [internalCheck setEnabled:YES];
        if ([[dic valueForKey:sInternalKey] intValue] == 0)
            [internalCheck setState:NSOffState];
        else
            [internalCheck setState:NSOnState];
        [applicationCheck setEnabled:YES];
        s = [dic valueForKey:sAppPathKey];
        [applicationPath setStringValue:(s == nil ? @"" : s)];
        if ([[dic valueForKey:sApplicationKey] intValue] == 0) {
            [applicationCheck setState:NSOffState];
            [selectButton setEnabled:NO];
            [applicationPath setEnabled:NO];
        } else {
            [applicationCheck setState:NSOnState];
            [selectButton setEnabled:YES];
            [applicationPath setEnabled:YES];
        }
    }
}

- (IBAction)devicePopUpSelected:(id)sender
{
    [self updateDisplay];
}

- (IBAction)selectApplication:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    int result;
    int n = (int)[devicePopUp selectedTag];
    NSMutableDictionary *dic;
    if (n < 0)
        return;
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"app", nil]];
    result = (int)[panel runModal];
    if (result == NSFileHandlingPanelOKButton) {
        NSURL *url = [panel URL];
        dic = [settings objectAtIndex:n];
        [dic setValue:[url path] forKey:sAppPathKey];
        [self updateDisplay];
    }
}

- (IBAction)checkBoxClicked:(id)sender
{
    int n = (int)[devicePopUp selectedTag];
    int state = ([sender state] == NSOnState);
    NSMutableDictionary *dic;
    if (n < 0)
        return;
    dic = [settings objectAtIndex:n];
    if (sender == internalCheck) {
        [dic setValue:[NSNumber numberWithInt:state] forKey:sInternalKey];
    } else if (sender == applicationCheck) {
        [dic setValue:[NSNumber numberWithInt:state] forKey:sApplicationKey];
    }
    [self updateDisplay];
}

- (IBAction)cancelClicked:(id)sender
{
    [[self window] orderOut:self];
    [settings release];
    settings = nil;
}

- (IBAction)saveClicked:(id)sender
{
    MyAppCallback_setObjectGlobalSettings(sPrefKey, settings);
    MyAppCallback_saveGlobalSettings();
    [[self window] orderOut:self];
    [settings release];
    settings = nil;
}

@end
