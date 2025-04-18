//
//  AudioSettingsPanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/13.
//  Copyright 2010-2024 Toshi Nagata. All rights reserved.
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

#import "AudioSettingsPanelController.h"
#import "AudioSettingsPrefPanelController.h"
#import "NSWindowControllerAdditions.h"
#import "AudioEffectPanelController.h"
#import "AUViewWindowController.h"
#import "MDHeaders.h"

/*  Tags for controls  */
/*  ...Base + 0: output, +1 ~ +8: bus 1 ~ 8  */
enum {
	kDevicePopUpBase = 100,
	kPanKnobBase = 200,
	kVolumeSliderBase = 300,
	kLeftLevelIndicatorBase = 400,
	kRightLevelIndicatorBase = 500,
	kCustomViewButtonBase = 600,
    kEffectButtonBase = 700,
	kBusIndexTextBase = 800
};
#define kOutputTagOffset 50

@implementation AudioSettingsPanelController

static AudioSettingsPanelController *sharedAudioSettingsPanelController;

+ (void)openAudioSettingsPanel
{
	if (sharedAudioSettingsPanelController == nil) {
		sharedAudioSettingsPanelController = [[AudioSettingsPanelController alloc] initWithWindowNibName: @"AudioSettingsPanel"];
	}
	[[sharedAudioSettingsPanelController window] makeKeyAndOrderFront: nil];
	[sharedAudioSettingsPanelController updateDisplay];
	[sharedAudioSettingsPanelController timerCallback:nil];
}

+ (AudioSettingsPanelController *)sharedAudioSettingsPanelController
{
    if (sharedAudioSettingsPanelController == nil)
        [AudioSettingsPanelController openAudioSettingsPanel];
    return sharedAudioSettingsPanelController;
}

/*  For debug  */
#if 0
static void printCFdata(CFTypeRef ref, int nestLevel)
{
    int i, count, typeid;
    const void **keys;
    typeid = (int)CFGetTypeID(ref);
    if (typeid == CFNumberGetTypeID()) {
        double dval;
        CFNumberGetValue(ref, kCFNumberDoubleType, &dval);
        fprintf(stderr, "%f\n", dval);
    } else if (typeid == CFStringGetTypeID()) {
        fprintf(stderr, "%s\n", CFStringGetCStringPtr(ref, kCFStringEncodingUTF8));
    } else if (typeid == CFDataGetTypeID()) {
        UInt64 len;
        len = CFDataGetLength(ref);
        fprintf(stderr, "data (%p) length (%llu)\n", (void *)ref, len);
    } else if (typeid == CFArrayGetTypeID()) {
        count = (int)CFArrayGetCount(ref);
        fprintf(stderr, "array {\n");
        for (i = 0; i < count; i++) {
            CFTypeRef eref = CFArrayGetValueAtIndex(ref, i);
            fprintf(stderr, "%*s%d: ", nestLevel + 2, "", i);
            printCFdata(eref, nestLevel + 2);
        }
        fprintf(stderr, "%*s}\n", nestLevel, "");
    } else if (typeid == CFDictionaryGetTypeID()) {
        count = (int)CFDictionaryGetCount(ref);
        keys = (const void **)malloc(sizeof(keys[0]) * count);
        if (keys == NULL) {
            fprintf(stderr, "*** memory allocation error (count = %d)\n", count);
            return;
        }
        CFDictionaryGetKeysAndValues(ref, keys, NULL);
        fprintf(stderr, "dictionary {\n");
        for (i = 0; i < count; i++) {
            CFTypeRef vref = CFDictionaryGetValue(ref, keys[i]);
            fprintf(stderr, "%*s[%s]: ", nestLevel + 2, "", CFStringGetCStringPtr((CFTypeRef)keys[i], kCFStringEncodingUTF8));
            printCFdata(vref, nestLevel + 2);
        }
        fprintf(stderr, "%*s}\n", nestLevel, "");
    } else {
        fprintf(stderr, "value of type %d (%p)\n", (int)CFGetTypeID(ref), (void *)ref);
    }
}
#endif

- (id)exportAudioSettingsToPropertyList
{
    int idx, isInput, deviceIndex, status, shouldSaveInternal;
    MDAudioDeviceInfo *dp;
    MDAudioMusicDeviceInfo *mp;
    MDAudioIOStreamInfo *iop;
    CFPropertyListRef pref;
    UInt32 prefSize = sizeof(pref);
    NSMutableDictionary *dic;

    dic = [NSMutableDictionary dictionary];
    for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
        NSMutableDictionary *dic2;
        const char *name;
        char key[40];
        if (idx >= kMDAudioFirstIndexForOutputStream)
            isInput = 0;
        else
            isInput = 1;
        if (isInput) {
            snprintf(key, sizeof key, "bus%d", idx + 1);
        } else {
            snprintf(key, sizeof key, "output%d", (idx - kMDAudioFirstIndexForOutputStream) + 1);
        }
        iop = MDAudioGetIOStreamInfoAtIndex(idx);
        deviceIndex = iop->deviceIndex;
        if (deviceIndex < 0) {
            /*  No device  */
            continue;
        } else if (deviceIndex < kMDAudioMusicDeviceIndexOffset) {
            dp = MDAudioDeviceInfoAtIndex(deviceIndex, isInput);
            name = dp->name;
        } else {
            mp = MDAudioMusicDeviceInfoAtIndex(deviceIndex - kMDAudioMusicDeviceIndexOffset);
            name = mp->name;
        }
        shouldSaveInternal = [AudioSettingsPrefPanelController shouldSaveInternalForDeviceName:name];
        dic2 = [NSMutableDictionary dictionary];
        [dic2 setObject:[NSString stringWithUTF8String:name] forKey:@"deviceName"];
        [dic setObject:dic2 forKey:[NSString stringWithUTF8String:key]];
        if (shouldSaveInternal) {
            pref = NULL;
            status = AudioUnitGetProperty(iop->unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, (AudioUnitElement)0, &pref, &prefSize);
            if (status == 0) {
                if (CFGetTypeID(pref) == CFDictionaryGetTypeID()) {
                    [dic2 setObject:pref forKey:@"classInfo"];
                }
                CFRelease(pref);
            }
        }
        [dic2 setObject:[NSNumber numberWithFloat:iop->pan] forKey:@"pan"];
        [dic2 setObject:[NSNumber numberWithFloat:iop->volume] forKey:@"volume"];
        if (iop->nchains > 0) {
            int ni;
            NSMutableArray *ary1, *ary2;
            ary1 = [NSMutableArray array];
            [dic2 setObject:ary1 forKey:@"effectChains"];
            for (ni = 0; ni < iop->nchains; ni++) {
                MDAudioEffectChain *cp = &(iop->chains[ni]);
                ary2 = [NSMutableArray array];
                [ary1 addObject:ary2];
                if (cp->neffects > 0) {
                    int ei;
                    for (ei = 0; ei < cp->neffects; ei++) {
                        CFPropertyListRef ppref;
                        NSMutableDictionary *dic3;
                        MDAudioEffect *ep = &(cp->effects[ei]);
                        dic3 = [NSMutableDictionary dictionary];
                        [ary2 addObject:dic3];
                        [dic3 setObject:[NSString stringWithUTF8String:ep->name] forKey:@"effectName"];
                        shouldSaveInternal = [AudioSettingsPrefPanelController shouldSaveInternalForDeviceName:ep->name];
                        if (shouldSaveInternal) {
                            ppref = NULL;
                            status = AudioUnitGetProperty(ep->unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, (AudioUnitElement)0, &ppref, &prefSize);
                            if (status == 0) {
                                [dic3 setObject:ppref forKey:@"classInfo"];
                                CFRelease(ppref);
                            }
                        }
                    }
                }
            }
        }
    }
    // printCFdata(dic, 0); /* for debug */
    return dic;
}

- (void)exportAudioSettings
{
    NSData *data;
    id plist;
    plist = [self exportAudioSettingsToPropertyList];
    if (plist == nil)
        return;
    data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error: NULL];
    if (data) {
        NSSavePanel *panel = [NSSavePanel savePanel];
        NSURL *url;
        [panel setNameFieldStringValue:@"audio_settings.xml"];
        if ([panel runModal] == NSFileHandlingPanelOKButton) {
            url = [panel URL];
            [data writeToURL:url atomically:YES];
        }
    }
}

- (void)importAudioSettingsFromPropertyList:(id)plist
{
    int map_current2plist[kMDAudioNumberOfStreams];
    int map_plist2current[kMDAudioNumberOfStreams];
    id plist4bus[kMDAudioNumberOfStreams];
    int i, j, k, isInput, deviceIndex, status, shouldLoadInternal;
    UInt32 psize = sizeof(id);
    MDAudioDeviceInfo *ap;
    MDAudioMusicDeviceInfo *mp;
    MDAudioIOStreamInfo *iop;
    id classInfo, num;
    for (i = 0; i < kMDAudioNumberOfStreams; i++) {
        char key[40];
        if (i >= kMDAudioFirstIndexForOutputStream)
            snprintf(key, sizeof key, "output%d", (i - kMDAudioFirstIndexForOutputStream) + 1);
        else
            snprintf(key, sizeof key, "bus%d", i + 1);
        plist4bus[i] = [plist valueForKey:[NSString stringWithUTF8String:key]];
        map_current2plist[i] = -1;
        map_plist2current[i] = -1;
    }
    for (i = 0; i < kMDAudioNumberOfStreams; i++) {
        const char *namep;
        if (plist4bus[i] == nil)
            continue;
        namep = [[plist4bus[i] valueForKey:@"deviceName"] UTF8String];
        deviceIndex = -1;
        if (i >= kMDAudioFirstIndexForOutputStream) {
            /*  Output stream  */
            isInput = 0;
            for (j = 0; (ap = MDAudioDeviceInfoAtIndex(j, isInput)) != NULL; j++) {
                if (strcmp(ap->name, namep) == 0) {
                    deviceIndex = j;
                    break;
                }
            }
            if (deviceIndex >= 0) {
                iop = MDAudioGetIOStreamInfoAtIndex(i);
                if (iop->deviceIndex != deviceIndex) {
                    /*  Change device  */
                    MDAudioSelectIOStreamDevice(i, deviceIndex);
                }
                /*  Set classInfo if present  */
                shouldLoadInternal = [AudioSettingsPrefPanelController shouldSaveInternalForDeviceName:ap->name];
                classInfo = [plist4bus[i] valueForKey:@"classInfo"];
                if (classInfo != nil && shouldLoadInternal) {
                    status = AudioUnitSetProperty(iop->unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, (AudioUnitElement)0, &classInfo, psize);
                    if (status != 0) {
                        fprintf(stderr, "*** cannot set classInfo to output bus %d (device %s)\n", (i - kMDAudioFirstIndexForOutputStream + 1), namep);
                    } else {
                        [classInfo retain];
                    }
                }
                /*  Set pan and volume  */
                num = [plist4bus[i] valueForKey:@"pan"];
                if (num)
                    MDAudioSetMixerPan(i, [num doubleValue]);
                num = [plist4bus[i] valueForKey:@"volume"];
                if (num)
                    MDAudioSetMixerVolume(i, [num doubleValue]);
            }
            continue;
        } else {
            /*  Input stream  */
            NSArray *ary1, *ary2;
            isInput = 1;
            for (j = 0; (ap = MDAudioDeviceInfoAtIndex(j, isInput)) != NULL; j++) {
                if (strcmp(ap->name, namep) == 0) {
                    deviceIndex = j;
                    break;
                }
            }
            if (deviceIndex < 0) {
                for (j = 0; (mp = MDAudioMusicDeviceInfoAtIndex(j)) != NULL; j++) {
                    if (strcmp(mp->name, namep) == 0) {
                        deviceIndex = j + kMDAudioMusicDeviceIndexOffset;
                        break;
                    }
                }
            }
            if (deviceIndex < 0) {
                NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                [alert setMessageText:@"Audio Settings Import Error"];
                [alert setInformativeText:[NSString stringWithFormat:@"No device %s is available.", namep]];
                [alert runModal];
                continue;
            }
            /*  Look up the existing audio/music input device  */
            k = -1;
            for (j = 0; j < kMDAudioNumberOfInputStreams; j++) {
                if (map_current2plist[j] != -1)
                    continue;  /*  This slot is already used  */
                iop = MDAudioGetIOStreamInfoAtIndex(j);
                if (iop->deviceIndex == deviceIndex) {
                    map_current2plist[j] = i;
                    map_plist2current[i] = j;
                    break;
                } else if (iop->deviceIndex == -1 && k == -1) {
                    k = j;  /*  Remember the first bus that is not used  */
                }
            }
            if (j >= kMDAudioNumberOfInputStreams) {
                /*  We need to open a new input device  */
                if (k == -1) {
                    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                    [alert setMessageText:@"Audio Settings Import Error"];
                    [alert setInformativeText:[NSString stringWithFormat:@"Cannot open %s: no empty input bus is available.", namep]];
                    [alert runModal];
                    return;
                }
                map_current2plist[k] = i;
                map_plist2current[i] = k;
                /*  Open the music device  */
                MDAudioSelectIOStreamDevice(k, deviceIndex);
            }
            /*  Set classInfo if present  */
            shouldLoadInternal = [AudioSettingsPrefPanelController shouldSaveInternalForDeviceName:namep];
            classInfo = [plist4bus[i] valueForKey:@"classInfo"];
            iop = MDAudioGetIOStreamInfoAtIndex(map_plist2current[i]);
            if (classInfo != nil && shouldLoadInternal) {
                [classInfo retain];
                status = AudioUnitSetProperty(iop->unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, (AudioUnitElement)0, &classInfo, psize);
                if (status != 0) {
                    fprintf(stderr, "*** cannot set classInfo to input bus %d (device %s)\n", i + 1, namep);
                }
            }
            /*  Set pan and volume  */
            num = [plist4bus[i] valueForKey:@"pan"];
            if (num)
                MDAudioSetMixerPan(map_plist2current[i], [num doubleValue]);
            num = [plist4bus[i] valueForKey:@"volume"];
            if (num)
                MDAudioSetMixerVolume(map_plist2current[i], [num doubleValue]);
            /*  Rebuild the effect chain  */
            /*  Dispose the existing effects  */
            while (iop->nchains > 0) {
                MDAudioEffectChain *cp = &(iop->chains[iop->nchains - 1]);
                while (cp->neffects > 0) {
                    MDAudioRemoveEffect(map_plist2current[i], iop->nchains - 1, cp->neffects - 1);
                }
                if (iop->nchains == 1)
                    break;
                MDAudioRemoveLastEffectChain(map_plist2current[i]);
            }
            /*  Creating the effect chains  */
            ary1 = [plist4bus[i] valueForKey:@"effectChains"];
            for (j = 0; j < [ary1 count]; j++) {
                ary2 = [ary1 objectAtIndex:j];
                if ([ary2 count] > 0 && j >= iop->nchains) {
                    /*  Append a new effect chain  */
                    MDAudioAppendEffectChain(map_plist2current[i]);
                }
                for (k = 0; k < [ary2 count]; k++) {
                    NSDictionary *dic = [ary2 objectAtIndex:k];
                    const char *enamep = [[dic valueForKey:@"effectName"] UTF8String];
                    int ei;
                    MDAudioEffect *ep;
                    ep = NULL;
                    for (ei = 0; (mp = MDAudioEffectDeviceInfoAtIndex(ei)) != NULL; ei++) {
                        if (strcmp(mp->name, enamep) == 0) {
                            status = MDAudioChangeEffect(map_plist2current[i], j, k, ei, 1);
                            if (status != 0) {
                                fprintf(stderr, "*** cannot create effect %s in effect chain %d-%d\n", enamep, j, k);
                            } else {
                                ep = &(iop->chains[j].effects[k]);
                                /*  Set classInfo if present  */
                                shouldLoadInternal = [AudioSettingsPrefPanelController shouldSaveInternalForDeviceName:enamep];
                                classInfo = [dic valueForKey:@"classInfo"];
                                if (classInfo != nil && shouldLoadInternal) {
                                    status = AudioUnitSetProperty(ep->unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, (AudioUnitElement)0, &classInfo, psize);
                                    if (status != 0) {
                                        fprintf(stderr, "*** cannot set classInfo to effect %s in effect chain %d-%d\n", enamep, j, k);
                                    } else {
                                        [classInfo retain];
                                    }
                                }
                                
                            }
                        }
                    }
                }
            }
        }
    }
    [self updateDisplay];
}

- (void)importAudioSettings
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    int result;
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"xml", nil]];
    result = (int)[panel runModal];
    if (result == NSFileHandlingPanelOKButton) {
        NSURL *url = [panel URL];
        NSData *data = [NSData dataWithContentsOfURL:url];
        NSPropertyListFormat plistFormat;
        id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:&plistFormat error:NULL];
        if (plist == NULL) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Audio Settings Import Error"];
            [alert setInformativeText:@"Cannot read the settings file."];
            [alert runModal];
            return;
        }
        //printCFdata(plist, 0); /* for debug */
        [self importAudioSettingsFromPropertyList:plist];
    }
}

- (void)updateDisplay
{
	int idx, i, n, isInput;
	NSMenu *menu;
	MDAudioDeviceInfo *dp;
	MDAudioMusicDeviceInfo *mp;
	if (knobValues == nil) {
		knobValues = [[NSMutableArray arrayWithCapacity:kMDAudioNumberOfStreams] retain];
		for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
			[knobValues addObject:[NSNumber numberWithFloat:0.0f]];
		}
	}
	for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
		id view;
		int tagOffset;
		if (idx >= kMDAudioFirstIndexForOutputStream) {
			isInput = 0;
			tagOffset = idx - kMDAudioFirstIndexForOutputStream + kOutputTagOffset;
		} else {
			isInput = 1;
			tagOffset = idx;
		}
		/*  Device PopUp button  */
		view = [self viewWithTag: kDevicePopUpBase + tagOffset];
		/*  Create menu  */
		menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
		[menu addItemWithTitle: @"(none)" action: nil keyEquivalent: @""];
		[[menu itemAtIndex: 0] setTag: -1];
		[menu addItem: [NSMenuItem separatorItem]];
		for (i = 0; (dp = MDAudioDeviceInfoAtIndex(i, isInput)) != NULL; i++) {
			[menu addItemWithTitle: [NSString stringWithUTF8String: dp->name] action: nil keyEquivalent: @""];
			[[menu itemAtIndex: i + 2] setTag: i + 1];
		}
		if (isInput) {
			[menu addItem: [NSMenuItem separatorItem]];
			n = i + 3;  /*  Number of items  */
			for (i = 0; (mp = MDAudioMusicDeviceInfoAtIndex(i)) != NULL; i++) {
				[menu addItemWithTitle: [NSString stringWithUTF8String: mp->name] action: nil keyEquivalent: @""];
				[[menu itemAtIndex: i + n] setTag: i + kMDAudioMusicDeviceIndexOffset + 1];
			}
		}
		[view setMenu: menu];
		MDAudioGetIOStreamDevice(idx, &n);
		if (n < 0)
			[view selectItemAtIndex: 0];
		else
			[view selectItemWithTag: n + 1];
		if (n >= 0 || !isInput) {
			view = [self viewWithTag: kPanKnobBase + tagOffset];
			[view setEnabled: (isInput != 0)];
			view = [self viewWithTag: kVolumeSliderBase + tagOffset];
			[view setEnabled: YES];
			view = [self viewWithTag: kLeftLevelIndicatorBase + tagOffset];
			[view setEnabled: YES];
			view = [self viewWithTag: kRightLevelIndicatorBase + tagOffset];
			[view setEnabled: YES];
			if (isInput) {
				view = [self viewWithTag: kCustomViewButtonBase + tagOffset];
				if (n >= kMDAudioMusicDeviceIndexOffset &&
                    (mp = MDAudioMusicDeviceInfoAtIndex(n - kMDAudioMusicDeviceIndexOffset)) != NULL &&
                    (mp->hasCustomView || [AudioSettingsPrefPanelController shouldCallApplicationForDeviceName:mp->name] != nil)) {
					[view setEnabled: YES];
					[view setState: NSOnState];
				} else {
					[view setEnabled: NO];
					[view setState: NSOffState];
				}
                view = [self viewWithTag: kEffectButtonBase + tagOffset];
                [view setEnabled: YES];
                [view setState: NSOnState];
			}
		} else {
			[[self viewWithTag: kPanKnobBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kVolumeSliderBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kLeftLevelIndicatorBase + tagOffset] setEnabled: NO];
			[[self viewWithTag: kRightLevelIndicatorBase + tagOffset] setEnabled: NO];
			view = [self viewWithTag: kCustomViewButtonBase + tagOffset];
			[view setEnabled: NO];
			[view setState: NSOffState];
            view = [self viewWithTag: kEffectButtonBase + tagOffset];
            [view setEnabled: NO];
            [view setState: NSOffState];
		}
	}
}

- (void)timerCallback: (NSTimer *)timer
{
	float pan, volume, ampLeft, ampRight, peakLeft, peakRight;
	int idx;
	if (![[self window] isVisible])
		return;
	for (idx = 0; idx < kMDAudioNumberOfStreams; idx++) {
        /*  Always update for all input/output channels  */
		if (MDAudioGetMixerBusAttributes(idx, &pan, &volume, &ampLeft, &ampRight, &peakLeft, &peakRight) == kMDNoError) {
			int tagOffset = (idx % kMDAudioFirstIndexForOutputStream) + (idx >= kMDAudioFirstIndexForOutputStream ? kOutputTagOffset : 0);
			ampLeft = (ampLeft * 1.6667f) + 100.0f;
			ampRight = (ampRight * 1.6667f) + 100.0f;
			if (ampLeft > 100.0f)
				ampLeft = 100.0f;
			if (ampLeft < 0.0f)
				ampLeft = 0.0f;
			if (ampRight > 100.0f)
				ampRight = 100.0f;
			if (ampRight < 0.0f)
				ampRight = 0.0f;
			/*  The pan slider uses 60-100 (for 0 to 0.5) and 0-40 (for 0.5 to 1.0) */
			[[self viewWithTag: kPanKnobBase + tagOffset] setFloatValue: (pan - 0.5f) * 80 + (pan < 0.5f ? 100 : 0)];
			[knobValues replaceObjectAtIndex:idx withObject:[NSNumber numberWithFloat:pan]];
			[[self viewWithTag: kVolumeSliderBase + tagOffset] setFloatValue: volume * 100.0f];
			[[self viewWithTag: kLeftLevelIndicatorBase + tagOffset] setFloatValue: ampLeft];
			[[self viewWithTag: kRightLevelIndicatorBase + tagOffset] setFloatValue: ampRight];
		}
	}
}

- (void)stopTimer
{
	if (timer != nil) {
		[timer invalidate];
		[timer release];
		timer = nil;
	}
}

- (IBAction)volumeSliderMoved:(id)sender
{
	int idx = (int)[sender tag] - kVolumeSliderBase;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	MDAudioSetMixerVolume(idx, [sender floatValue] * 0.01f);
}

- (IBAction)panKnobMoved:(id)sender
{
	float pan, opan;
	int idx = (int)[sender tag] - kPanKnobBase;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	pan = [sender floatValue];
	pan = (pan >= 50.0f ? pan - 100.0f : pan) / 80.0f + 0.5f;
	opan = [[knobValues objectAtIndex:idx] floatValue];
	if (pan < 0.0f || pan > 1.0f || (opan < 0.25f && pan > 0.75f) || (opan > 0.75f && pan < 0.25f)) {
		/*  Do not change value  */
		[sender setFloatValue:(opan - 0.5f) * 80 + (opan < 0.5f ? 100 : 0)];
		return;
	}
	[knobValues replaceObjectAtIndex:idx withObject:[NSNumber numberWithFloat:pan]];
	MDAudioSetMixerPan(idx, pan);
}

- (IBAction)myPopUpAction: (id)sender
{
	int idx = (int)[sender tag] - kDevicePopUpBase;
	int dev = (int)[[sender selectedItem] tag];
	if (dev > 0)
		dev--;
	if (idx >= kOutputTagOffset)
		idx += (kMDAudioFirstIndexForOutputStream - kOutputTagOffset);
	MDAudioSelectIOStreamDevice(idx, dev);
	[self updateDisplay];
}

- (IBAction)customViewButtonPressed: (id)sender
{
	int idx = (int)[sender tag] - kCustomViewButtonBase;
	if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
		int dev;
		MDAudioGetIOStreamDevice(idx, &dev);
		if (dev >= kMDAudioMusicDeviceIndexOffset) {
			MDAudioIOStreamInfo *ip;
			ip = MDAudioGetIOStreamInfoAtIndex(idx);
			if (ip != NULL && ip->unit != NULL) {
				char *name = NULL;
                MDAudioMusicDeviceInfo *mp = MDAudioMusicDeviceInfoAtIndex(ip->deviceIndex - kMDAudioMusicDeviceIndexOffset);
                id appName = [AudioSettingsPrefPanelController shouldCallApplicationForDeviceName:mp->name];
                if (appName != nil) {
                    [[NSWorkspace sharedWorkspace] launchApplication:appName];
                } else {
                    id cont = [AUViewWindowController windowControllerForAudioUnit: ip->unit cocoaView:(mp->hasCustomView == kMDAudioHasCocoaView) delegate: nil];
                    if (ip->midiControllerName != NULL)
                        name = ip->midiControllerName;
                    else {
                        if (mp != NULL && mp->name != NULL)
                            name = mp->name;
                    }
                    if (name != NULL)
                        [[cont window] setTitle: [NSString stringWithUTF8String: name]];
                }
			}
		}
	}
}

- (IBAction)effectButtonPressed: (id)sender
{
    int idx = (int)[sender tag] - kEffectButtonBase;
    if (idx >= 0 && idx < kMDAudioNumberOfInputStreams) {
        AudioEffectPanelController *cont = (AudioEffectPanelController *)effectControllers[idx];
        if (cont != nil) {
            [[cont window] makeKeyAndOrderFront:self];
        } else {
            cont = [[AudioEffectPanelController alloc] initWithBusIndex:idx];
            [[cont window] makeKeyAndOrderFront:self];
            effectControllers[idx] = cont;
        }
    }
}

- (void)windowDidLoad
{
    int i, count;

    [super windowDidLoad];
	
	//  Create bus controller list
	{
		static int sTagsToCopy[] = {
			kDevicePopUpBase, kPanKnobBase, kVolumeSliderBase,
			kLeftLevelIndicatorBase, kRightLevelIndicatorBase, kCustomViewButtonBase,
            kEffectButtonBase, kBusIndexTextBase,
			0  /*  This is dummy to copy the horizontal line  */
		};
		NSPoint pt = [separatorLine frame].origin;
		NSRect frame = [busListView frame];
		float busHeight = frame.size.height - pt.y;
		frame.size.height = busHeight * kMDAudioNumberOfInputStreams;
		[busListView setFrame:frame];
		for (count = 1; count < kMDAudioNumberOfInputStreams; count++) {
			for (i = 0; i < sizeof(sTagsToCopy) / sizeof(sTagsToCopy[0]); i++) {
				NSView *view, *newview;
				NSData *data;
				NSRect vframe;
				int tag = sTagsToCopy[i];
				if (tag == 0)
					view = separatorLine;
				else
					view = [self viewWithTag:tag];
				data = [NSKeyedArchiver archivedDataWithRootObject:view];
				newview = [NSKeyedUnarchiver unarchiveObjectWithData:data];
				if (tag != 0)
					[(id)newview setTag:tag + count];
				if (tag == kBusIndexTextBase)
					[(id)newview setStringValue:[NSString stringWithFormat:@"Bus %d", count + 1]];
				vframe = [view frame];
				vframe.origin.y -= count * busHeight;
				[newview setFrame:vframe];
				[busListView addSubview:newview];
			}
		}
		[busListView scrollPoint:NSMakePoint(0, frame.size.height - [[busListView superview] frame].size.height)];
	}
	
	if (timer == nil) {
		timer = [[NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector:@selector(timerCallback:) userInfo:nil repeats:YES] retain];
	}
    if (effectControllers == NULL) {
        effectControllers = (id *)calloc(sizeof(id), kMDAudioNumberOfInputStreams);
    }
	[self updateDisplay];
}

@end
