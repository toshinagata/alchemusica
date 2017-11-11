/*
 *  MDPlayer_MacOSX.c
 *
 *  Created by Toshi Nagata on Sun Jul 01 2001.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"
#include "MDPlayer_MacOSX.h"
#include "MDAudio.h"

/*  Define macros such as 'AVAILABLE_MAC_OS_X_VERSION_10_0_AND_LATER'; these are used in AUGraph.h etc. */
/*  AUGraph.h (and maybe other headers) must really include this header; maybe I need to file a bug. */
#include <AvailabilityMacros.h>

//#define USE_TIME_MANAGER 1

#if !USE_TIME_MANAGER
#include <pthread.h>
#else
#include <CoreServices/CoreServices.h>		/*  for Time Manager (Classic MacOS-like -> obsolete in Mac OS 10.4)  */
#endif

#include <CoreMIDI/CoreMIDI.h>				/*  for MIDI input/output  */
#include <CoreAudio/CoreAudio.h>			/*  for AudioConvertNanosToHostTime()  */
/*#include <unistd.h>							*//*  for usleep()  */

#pragma mark ====== Definitions ======

#if USE_TIME_MANAGER
typedef struct MyTMTask {
	TMTask tmTask;
	MDPlayer *player;
} MyTMTask;
#endif

#define kInvalidUniqueID 0

typedef struct MDMIDIDeviceRecord {
    MIDIEndpointRef eref;               /*  CoreMIDI endpoint  */
    MIDISysexSendRequest sysexRequest;  /*  Sysex send request  */
    MIDIPacketList	packetList;         /*  MIDI packet list  */
} MDMIDIDeviceRecord;

typedef struct MDPatchNameRecord {
    UInt32 instno;  /*  0xMMLLPP, MM: bank MSB, LL: bank LSB, PP: program number  */
    char *name;
} MDPatchNameRecord;

typedef struct MDDeviceIDRecord {
	char *      name;
	
	/*  OS-specific fields for identification of devices  */
    /*  Only one of uniqueID or streamIndex is valid  */
    int         streamIndex;    /*  MDAudioIOStream index (= bus index of Audio setup)  */
	int         uniqueID;       /*  CoreMIDI device  */
    MDMIDIDeviceRecord *midiRec;  /*  CoreMIDI device record (malloc'ed)  */
    
    /*  Patch names  */
    int         npatches;
    MDPatchNameRecord *patches;

} MDDeviceIDRecord;

typedef struct MDDeviceInfo {
	char		initialized;	/*  non-zero if already initialized  */
	int32_t		destNum;		/*  The number of destinations  */
	MDDeviceIDRecord *dest;		/*  The names of destinations  */
	int32_t		sourceNum;		/*  The number of sources  */
	MDDeviceIDRecord *source;	/*  The names of sources  */
} MDDeviceInfo;

static MDDeviceInfo sDeviceInfo = { 0, 0, NULL, 0, NULL };

/*  Information for MIDI output  */
typedef struct MDDestinationInfo {
	int32_t	refCount;
	int32_t	dev;                /*  Index to sDeviceInfo.dest[]  */

	/*  CoreMIDI (Mac OS X) specfic fields  */
	int32_t	bytesToSend;
    int numEvents;
//	MIDIEndpointRef	eref;         /*  MIDI device  */
//    MusicDeviceComponent comp;    /*  MusicDevice  */
//    int streamIndex;              /*  Index of MDAudioIOStreamInfo (same as MDDeviceIDRecord.streamIndex) */
    MIDIPacketList	packetList;
	MIDIPacket *	packetPtr;
	MDTimeType		timeOfLastEvent;
	MIDISysexSendRequest	sysexRequest;
	unsigned char	sysexTransmitting;		/* non-zero if sysexRequest is being processed */

    MDTrackMerger * merger;
    MDEvent *       currentEp;
    MDTrack *       currentTrack;
    MDTickType      currentTick;
    MDTrack *		noteOff;		/*  Keep the 'internal' note off  */
    MDPointer *		noteOffPtr;
    MDTickType		noteOffTick;

} MDDestinationInfo;

#define MIDIObjectNull ((MIDIObjectRef)0)

/*  CoreMIDI (Mac OS X) specific static variables  */
static MIDIClientRef	sMIDIClientRef = MIDIObjectNull;
static MIDIPortRef		sMIDIInputPortRef = MIDIObjectNull;
static MIDIPortRef		sMIDIOutputPortRef = MIDIObjectNull;

/*  Forward declaration of the MIDI read callback  */
static void MyMIDIReadProc(const MIDIPacketList *pktlist, void *refCon, void *connRefCon);

#define kMDRecordingBufferSize	32768
/*#define kMDRecordingBufferSize	99  *//*  Small buffer for debugging  */

typedef struct MDRecordingBuffer {
    struct MDRecordingBuffer *next;
    int32_t size;
    unsigned char data[4];
} MDRecordingBuffer;

typedef struct MDRecordingEventHeader {
    MDTimeType	timeStamp;
    int32_t size;
} MDRecordingEventHeader;

struct MDPlayer {
	int32_t			refCount;
    MDSequence *    sequence;
	MDCalibrator *	calib;		/*  for tick <-> time conversion  */
	MDTimeType		time;		/*  the last time when interrupt fired  */
	MDTimeType		startTime;	/*  In microseconds  */
	MDTickType		lastTick;	/*  tick of the last event already sent  */
	MDPlayerStatus	status;
    unsigned char   shouldTerminate; /*  Flag to request the playing thread to terminate */
    
    /*  Destination list  */
	int32_t			destNum;		/*  The number of destinations used in this player  */
	MDDestinationInfo	**destInfo;	/*  Information for MIDI output  */

    /*  Metronome status  */
    MDTickType		nextMetronomeBar;  /*  Tick to ring the metronome bell (top of bar)  */
	MDTickType		nextMetronomeBeat; /*  Tick to ring the metronome click (each beat)  */
	int             metronomeBar;      /*  Bar length  */
	int             metronomeBeat;     /*  Beat length  */
	MDTickType      nextTimeSignature; /*  Next time signature change for metronome  */

    /*  Count-off metronome  */
    MDTimeType      countOffDuration;  /*  Time (in microseconds) for count-off  */
    MDTimeType      countOffEndTime;   /*  End time for count-off  */
    MDTimeType      countOffBar;       /*  Bar duration for count-off; if zero, then only beat tap will be sent out  */
    MDTimeType      countOffBeat;      /*  Beat duration for count-off  */
    MDTimeType      countOffFirstRing; /*  First time for count-off metronome note  */
    MDTimeType      countOffNextRing;  /*  Last time for count-off metronome note  */
    
    /*  Recording info  */
    unsigned char	isRecording;
    MDTickType      recordingStopTick;
    
	MDAudio *		audio;

    /*  Recording buffer  */
    MDRecordingBuffer *topBuffer;
    int32_t topPos;
    int32_t topSize;
    MDRecordingBuffer *bottomBuffer;
    int32_t bottomPos;
    int32_t bottomSize;
    MDRecordingBuffer *topFreeBuffer;
    MDRecordingBuffer *bottomFreeBuffer;

    /*  Temporary storage for converting recorded data to MDEvent  */
    unsigned char *	tempStorage;
    int32_t			tempStorageSize;
    int32_t			tempStorageLength;
    int32_t			tempStorageIndex;
    unsigned char	runningStatusByte;

	/*  CoreMIDI (Mac OS X) specific fields  */
#if !USE_TIME_MANAGER
	pthread_t  playThread;
	
#else
	MyTMTask		myTMTask;
#endif
};

static MDPlayer *sRecordingPlayer = NULL;	/*  the MDPlayer that receives the incoming MIDI messages */

/*  TODO: Don't use MIDI device directly. Use MDDestinationInfo instead.  */
//static int32_t sMIDIThruDevice = -1;
//static MIDIEndpointRef sMIDIThruDeviceRef = MIDIObjectNull;

//static MDDestinationInfo *sMIDIThruDestination = NULL;
static int32_t sMIDIThruDevice = -1;
static int sMIDIThruChannel = 0; /*  0..15; if 16, then incoming channel number is kept */
static int sMIDIThruTranspose = 0;

/*  Minimum interval of interrupts  */
#define	kMDPlayerMinimumInterval	50000   /* 50 msec */
#define kMDPlayerMaximumInterval    100000  /* 100 msec */

/*  Prefetch interval  */
#define kMDPlayerPrefetchInterval	100000  /* 100 msec */

MetronomeInfoRecord gMetronomeInfo;

#pragma mark ====== Utility function  ======

int
my_usleep(uint32_t useconds)
{
	struct timespec req_time, rem_time;
	req_time.tv_sec = useconds / 1000000;
	req_time.tv_nsec = (useconds % 1000000) * 1000;
	return nanosleep(&req_time, &rem_time);
}

#pragma mark ====== Device Management ======

static void
MDPlayerDumpNames(MIDIObjectRef ref)
{
	CFStringRef name;
	char buf[256];
	MIDIObjectGetStringProperty(ref, kMIDIPropertyManufacturer, &name);
	CFStringGetCString(name, buf, 255, CFStringGetSystemEncoding());
	fprintf(stderr, "Manufacturer = %s\n", buf);
	CFRelease(name);
	MIDIObjectGetStringProperty(ref, kMIDIPropertyModel, &name);
	CFStringGetCString(name, buf, 255, CFStringGetSystemEncoding());
	fprintf(stderr, "Model = %s\n", buf);
	CFRelease(name);
	MIDIObjectGetStringProperty(ref, kMIDIPropertyName, &name);
	CFStringGetCString(name, buf, 255, CFStringGetSystemEncoding());
	fprintf(stderr, "Name = %s\n", buf);
	CFRelease(name);
}

static void
MDPlayerReloadDeviceInformationSub(MDDeviceIDRecord **src_dst_p, int32_t *src_dst_Num_p, int is_dst)
{
	MIDIEndpointRef eref, eref1;
	MIDIDeviceRef dref;
	MIDIEntityRef entref;
	CFStringRef name, devname, name1;
	int32_t n, dev, ent, en, num;
	char buf[256], *p;
	SInt32 uniqueID;
	int i;

	/*  Look up all src/dst, compare the unique ID, and update the name  */
	num = (int)(is_dst ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources());
	for (n = 0; n < num; n++) {
		eref = (is_dst ? MIDIGetDestination(n) : MIDIGetSource(n));
		MIDIObjectGetStringProperty(eref, kMIDIPropertyName, &name);
		if (MIDIObjectGetIntegerProperty(eref, kMIDIPropertyUniqueID, &uniqueID) != noErr)
			uniqueID = 0;
		/*  Search the device/entity/endpoint tree  */
		for (dev = (int)MIDIGetNumberOfDevices() - 1; dev >= 0; dev--) {
			dref = MIDIGetDevice(dev);
			for (ent = (int)MIDIDeviceGetNumberOfEntities(dref) - 1; ent >= 0; ent--) {
				entref = MIDIDeviceGetEntity(dref, ent);
				en = (int)(is_dst ? MIDIEntityGetNumberOfDestinations(entref) : MIDIEntityGetNumberOfSources(entref)) - 1;
				for ( ; en >= 0; en--) {
					eref1 = (is_dst ? MIDIEntityGetDestination(entref, en) : MIDIEntityGetSource(entref, en));
					if (eref1 == eref)
						goto found1;
				}
			}
		}
	found1:
		if (dev >= 0) {
			MIDIObjectType objType;
			MIDIObjectRef oref;
			SInt32 uid;
			if (MIDIObjectGetIntegerProperty(eref, kMIDIPropertyConnectionUniqueID, &uid) == noErr
			&& uid != 0
			&& MIDIObjectFindByUniqueID(uid, &oref, &objType) == noErr) {
				MDPlayerDumpNames(oref);
				MIDIObjectGetStringProperty(oref, kMIDIPropertyName, &name);
			} else {
				MIDIObjectGetStringProperty(dref, kMIDIPropertyName, &devname);
				name1 = name;
				name = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@-%@"), devname, name);
				CFRelease(name1);
				CFRelease(devname);
			}
		}
		if (!CFStringGetCString(name, buf, 255, kCFStringEncodingUTF8))
			sprintf(buf, "(Device %d)", n);
		buf[255] = 0;
		/*  Look up in the existing table whether this device is already there (by uniqueID) */
		for (i = 0; i < *src_dst_Num_p; i++) {
			if ((*src_dst_p)[i].uniqueID == uniqueID)
				break;
		}
		if (i >= 0 && i < *src_dst_Num_p) {
			/*  If found, then update the name and eref */
			p = (*src_dst_p)[i].name;
			if (p == NULL || strcmp(p, buf) != 0) {
				if (p != NULL)
					free(p);
				p = (char *)malloc(strlen(buf) + 1);
				strcpy(p, buf);
				(*src_dst_p)[i].name = p;
			}
		} else {
			/*  Look up by device name, and create a new entry if not found  */
			i = (is_dst ? MDPlayerAddDestinationName(buf) : MDPlayerAddSourceName(buf));
        }
        /*  And update the uniqueID  */
        if (i >= 0 && i < *src_dst_Num_p) {
            MDDeviceIDRecord *dp = *src_dst_p + i;
            if (dp->midiRec == NULL) {
                dp->midiRec = (MDMIDIDeviceRecord *)calloc(sizeof(MDMIDIDeviceRecord), 1);
                if (dp->midiRec == NULL)
                    return;
                /*  Raise sysex completion flag (to enable sysex sending)  */
                dp->midiRec->sysexRequest.complete = 1;
            }
            dp->uniqueID = uniqueID;
            dp->streamIndex = -1;
            dp->midiRec->eref = eref;
        }
	}

    /*  Handle MusicDevice  */
    if (is_dst) {
        MDAudioIOStreamInfo *ip;
        int j;
        for (i = 0; i < kMDAudioNumberOfInputStreams; i++) {
            ip = MDAudioGetIOStreamInfoAtIndex(i);
            if (ip->midiControllerName == NULL)
                continue;
            for (j = 0; j < *src_dst_Num_p; j++) {
                p = (*src_dst_p)[j].name;
                if (p == NULL || strcmp(p, ip->midiControllerName) == 0)
                    break;
            }
            if (j >= *src_dst_Num_p) {
                j = MDPlayerAddDestinationName(ip->midiControllerName);
            }
            if (j >= 0 && j < *src_dst_Num_p) {
                /*  Update the device info  */
                (*src_dst_p)[j].uniqueID = kInvalidUniqueID;
                (*src_dst_p)[j].midiRec = NULL;
                (*src_dst_p)[j].streamIndex = i;
                MDPlayerUpdatePatchNames(j);
            }
        }
    }
}

static void
sCoreMIDINotifyProc(const MIDINotification *message, void *refCon)
{
	if (message->messageID == kMIDIMsgSetupChanged) {
	//	MDPlayerReloadDeviceInformation();
		MDPlayerNotificationCallback();
	}
}

/* --------------------------------------
	･ MDPlayerInitCoreMIDI
   -------------------------------------- */
void
MDPlayerInitCoreMIDI(void)
{
	if (sDeviceInfo.initialized)
		return;

	if (sMIDIClientRef == MIDIObjectNull)
		MIDIClientCreate(CFSTR("Alchemusica"), sCoreMIDINotifyProc, NULL, &sMIDIClientRef);
	if (sMIDIOutputPortRef == MIDIObjectNull)
		MIDIOutputPortCreate(sMIDIClientRef, CFSTR("Output port"), &sMIDIOutputPortRef);
	if (sMIDIInputPortRef == MIDIObjectNull)
		MIDIInputPortCreate(sMIDIClientRef, CFSTR("Input port"), MyMIDIReadProc, NULL, &sMIDIInputPortRef);
	sDeviceInfo.initialized = 1;
}

/* --------------------------------------
	･ MDPlayerReloadDeviceInformation
   -------------------------------------- */
void
MDPlayerReloadDeviceInformation(void)
{
    int n;
    
	if (!sDeviceInfo.initialized)
		MDPlayerInitCoreMIDI();
    
    /*  Disconnect the previous MIDI sources from the input port  */
    for (n = 0; n < sDeviceInfo.sourceNum; n++) {
        if (sDeviceInfo.source[n].uniqueID != kInvalidUniqueID) {
            MIDIPortDisconnectSource(sMIDIInputPortRef, sDeviceInfo.source[n].midiRec->eref);
        }
    }

	/*  Update the device information  */
	/*  The device index to the same device [i.e. the device with the same uniqueID] remains the same.  */
	MDPlayerReloadDeviceInformationSub(&(sDeviceInfo.dest), &(sDeviceInfo.destNum), 1);
	MDPlayerReloadDeviceInformationSub(&(sDeviceInfo.source), &(sDeviceInfo.sourceNum), 0);

    /*  Connect the updated MIDI sources to the input port  */
    for (n = 0; n < sDeviceInfo.sourceNum; n++) {
        if (sDeviceInfo.source[n].uniqueID != kInvalidUniqueID) {
            MIDIPortConnectSource(sMIDIInputPortRef, sDeviceInfo.source[n].midiRec->eref, (void *)(intptr_t)n);
        }
    }
}

/* --------------------------------------
	･ MDPlayerGetNumberOfDestinations
   -------------------------------------- */
int32_t
MDPlayerGetNumberOfDestinations(void)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	return sDeviceInfo.destNum;
}

/* --------------------------------------
	･ MDPlayerGetDestinationName
   -------------------------------------- */
MDStatus
MDPlayerGetDestinationName(int32_t dev, char *name, int32_t sizeof_name)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	if (dev >= 0 && dev < sDeviceInfo.destNum) {
		strncpy(name, sDeviceInfo.dest[dev].name, sizeof_name - 1);
		name[sizeof_name - 1] = 0;
		return kMDNoError;
	} else {
		name[0] = 0;
		return kMDErrorBadDeviceNumber;
	}
}

/* --------------------------------------
	･ MDPlayerGetDestinationNumberFromName
   -------------------------------------- */
int32_t
MDPlayerGetDestinationNumberFromName(const char *name)
{
    int32_t dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.destNum; dev++) {
        if (strcmp(name, sDeviceInfo.dest[dev].name) == 0)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerGetNumberOfSources
   -------------------------------------- */
int32_t
MDPlayerGetNumberOfSources(void)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	return sDeviceInfo.sourceNum;
}

/* --------------------------------------
	･ MDPlayerGetSourceName
   -------------------------------------- */
MDStatus
MDPlayerGetSourceName(int32_t dev, char *name, int32_t sizeof_name)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	if (dev >= 0 && dev < sDeviceInfo.sourceNum) {
		strncpy(name, sDeviceInfo.source[dev].name, sizeof_name - 1);
		name[sizeof_name - 1] = 0;
		return kMDNoError;
	} else {
		name[0] = 0;
		return kMDErrorBadDeviceNumber;
	}
}

/* --------------------------------------
	･ MDPlayerGetSourceNumberFromName
   -------------------------------------- */
int32_t
MDPlayerGetSourceNumberFromName(const char *name)
{
    int32_t dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.sourceNum; dev++) {
        if (strcmp(name, sDeviceInfo.source[dev].name) == 0)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerAddDestinationName
   -------------------------------------- */
int32_t
MDPlayerAddDestinationName(const char *name)
{
	int32_t dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	dev = MDPlayerGetDestinationNumberFromName(name);
	if (dev < 0) {
		/*  Expand the array  */
		MDDeviceIDRecord *idp;
		dev = sDeviceInfo.destNum;
		if (sDeviceInfo.dest != NULL)
			idp = (MDDeviceIDRecord *)realloc(sDeviceInfo.dest, sizeof(MDDeviceIDRecord) * (dev + 1));
		else
			idp = (MDDeviceIDRecord *)malloc(sizeof(MDDeviceIDRecord) * (dev + 1));
		memset(&idp[dev], 0, sizeof(MDDeviceIDRecord));
		idp[dev].name = (char *)malloc(strlen(name) + 1);
		strcpy(idp[dev].name, name);
		sDeviceInfo.dest = idp;
		sDeviceInfo.destNum = dev + 1;
	}
	return dev;
}

/* --------------------------------------
	･ MDPlayerAddSourceName
   -------------------------------------- */
int32_t
MDPlayerAddSourceName(const char *name)
{
	int32_t dev;
	dev = MDPlayerGetSourceNumberFromName(name);
	if (dev < 0) {
		/*  Expand the array  */
		MDDeviceIDRecord *idp;
		dev = sDeviceInfo.sourceNum;
		if (sDeviceInfo.source != NULL)
			idp = (MDDeviceIDRecord *)realloc(sDeviceInfo.source, sizeof(MDDeviceIDRecord) * (dev + 1));
		else
			idp = (MDDeviceIDRecord *)malloc(sizeof(MDDeviceIDRecord) * (dev + 1));
		memset(&idp[dev], 0, sizeof(MDDeviceIDRecord));
		idp[dev].name = (char *)malloc(strlen(name) + 1);
		strcpy(idp[dev].name, name);
		sDeviceInfo.source = idp;
		sDeviceInfo.sourceNum = dev + 1;
	}
	return dev;
}

/* --------------------------------------
	･ MDPlayerUpdatePatchNames
 -------------------------------------- */
/*  Update the patch name info for the given device. */
int
MDPlayerUpdatePatchNames(int32_t dev)
{
    MDDeviceIDRecord *rp;
    int i;
    if (dev < 0 || dev >= sDeviceInfo.destNum)
        return -1;  /*  Invalid device  */
    rp = &(sDeviceInfo.dest[dev]);
    if (rp->uniqueID != kInvalidUniqueID) {
        /*  TODO: Implement patch list for external MIDI device  */
        return -1;
    } else if (rp->streamIndex >= 0) {
        /*  MusicDevice  */
        OSStatus err;
        UInt32 count, instno;
        UInt32 datasize;
        MDAudioIOStreamInfo *mp = MDAudioGetIOStreamInfoAtIndex(rp->streamIndex);
        if (mp == NULL)
            return -1;
        datasize = sizeof(UInt32);
        err = AudioUnitGetProperty(mp->unit, kMusicDeviceProperty_InstrumentCount, kAudioUnitScope_Global, 0, &count, &datasize);
        if (err != noErr)
            return -1;
        if (rp->npatches > 0) {
            /*  Free previous info  */
            for (i = 0; i < rp->npatches; i++) {
                free(rp->patches[i].name);
            }
            free(rp->patches);
            rp->patches = NULL;
            rp->npatches = 0;
        }
        if (count > 0) {
            rp->patches = (MDPatchNameRecord *)calloc(sizeof(MDPatchNameRecord), count);
            rp->npatches = 0;
            for (i = 0; i < count; i++) {
                char name[256];
                datasize = sizeof(instno);
                err = AudioUnitGetProperty(mp->unit, kMusicDeviceProperty_InstrumentNumber, kAudioUnitScope_Global, i, &instno, &datasize);
                if (err != noErr)
                    continue;
                datasize = sizeof(name);
                err = AudioUnitGetProperty(mp->unit, kMusicDeviceProperty_InstrumentName, kAudioUnitScope_Global, instno, name, &datasize);
                if (err != noErr)
                    continue;
                rp->patches[rp->npatches].instno = instno;
                rp->patches[rp->npatches].name = strdup(name);
                rp->npatches++;
            }
        }
        return rp->npatches;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerGetNumberOfPatchNames
 -------------------------------------- */
/*  Returns the number of available patch names. */
int
MDPlayerGetNumberOfPatchNames(int32_t dev)
{
    if (dev >= 0 && dev < sDeviceInfo.destNum) {
        return sDeviceInfo.dest[dev].npatches;
    } else return 0;
}
    
/* --------------------------------------
	･ MDPlayerGetPatchName
 -------------------------------------- */
/*  Returns the patch name if available. If bank is -1, then progno is the index that
    scans all registered patch information. If bank is 0xMMLL (MM and LL are the bank
    select MSB and LSB), then the progno is the program number (0-127).
    Returns the patch number (0xMMLLPP) if the patch name is available, -1 otherwise */
int
MDPlayerGetPatchName(int32_t dev, int bank, int progno, char *name, int32_t sizeof_name)
{
    int idx = -1;
    if (dev >= 0 && dev < sDeviceInfo.destNum) {
        if (bank == -1) {
            if (progno >= 0 && progno < sDeviceInfo.dest[dev].npatches)
                idx = progno;
        } else if (progno >= 0 && progno < 128) {
            /*  Look for the given bank and program  */
            UInt32 instno = (bank << 8) + progno;
            for (idx = sDeviceInfo.dest[dev].npatches - 1; idx >= 0; idx--) {
                MDPatchNameRecord *pr = &(sDeviceInfo.dest[dev].patches[idx]);
                if (pr->instno == instno)
                    break;
            }
        }
    }
    if (idx >= 0) {
        strncpy(name, sDeviceInfo.dest[dev].patches[idx].name, sizeof_name - 1);
        name[sizeof_name - 1] = 0;
        return sDeviceInfo.dest[dev].patches[idx].instno;
    } else return -1;
}

/* --------------------------------------
	･ MDPlayerInitDestinationInfo
   -------------------------------------- */
static void
MDPlayerInitDestinationInfo(MDDestinationInfo *info, int32_t dev)
{
    info->dev = dev;
	info->bytesToSend = 0;
	info->sysexTransmitting = 0;
	info->packetPtr = MIDIPacketListInit(&info->packetList);
}

/* --------------------------------------
	･ MDPlayerNewDestinationInfo
   -------------------------------------- */
static MDDestinationInfo *
MDPlayerNewDestinationInfo(int32_t dev)
{
	MDDestinationInfo *info;
	info = (MDDestinationInfo *)malloc(sizeof(MDDestinationInfo));
	if (info == NULL)
		return NULL;
	memset(info, 0, sizeof(MDDestinationInfo));
	info->refCount = 1;
	MDPlayerInitDestinationInfo(info, dev);
	return info;
}

/* --------------------------------------
	･ MDPlayerReleaseDestinationInfo
   -------------------------------------- */
static void
MDPlayerReleaseDestinationInfo(MDDestinationInfo *info)
{
	if (info != NULL) {
		info->refCount--;
		if (info->refCount == 0) {
            if (info->merger != NULL)
                MDTrackMergerRelease(info->merger);
            if (info->noteOffPtr != NULL)
                MDPointerRelease(info->noteOffPtr);
            if (info->noteOff != NULL)
                MDTrackRelease(info->noteOff);
			free(info);
		}
	}
}

#pragma mark ====== Internal MIDI Functions ======

#if DEBUG
static FILE *sMIDIInputDump;
#endif

static void
MDPlayerReleaseRecordingBuffer(MDPlayer *inPlayer)
{
    MDRecordingBuffer *buf1, *buf2;
    if (inPlayer == NULL)
        return;
    buf1 = inPlayer->bottomBuffer;
    while (buf1 != NULL) {
        buf2 = buf1->next;
        free(buf1);
        buf1 = buf2;
    }
    buf1 = inPlayer->bottomFreeBuffer;
    while (buf1 != NULL) {
        buf2 = buf1->next;
        free(buf1);
        buf1 = buf2;
    }
    inPlayer->topBuffer = inPlayer->bottomBuffer = NULL;
    inPlayer->topFreeBuffer = inPlayer->bottomFreeBuffer = NULL;
    inPlayer->topPos = inPlayer->bottomPos = inPlayer->topSize = inPlayer->bottomSize = 0;
}

static MDRecordingBuffer *
AllocateOneRecordingBuffer(void)
{
    MDRecordingBuffer *buf;
    buf = (MDRecordingBuffer *)malloc(sizeof(MDRecordingBuffer) - 4 + kMDRecordingBufferSize);
    if (buf != NULL) {
        memset(buf, 0, sizeof(MDRecordingBuffer) - 4 + kMDRecordingBufferSize);
        buf->size = kMDRecordingBufferSize;
    }
    return buf;
}

static MDRecordingBuffer *
MDPlayerAllocateRecordingBuffer(MDPlayer *inPlayer)
{
    MDRecordingBuffer *buf;
    if (inPlayer == NULL)
        return NULL;
    if (inPlayer->topBuffer == NULL) {
        /*  First invocation: allocate one buffer for immediate use, and
            two buffers for later use  */
        buf = AllocateOneRecordingBuffer();
        if (buf == NULL)
            return NULL;
        inPlayer->topBuffer = inPlayer->bottomBuffer = buf;
        inPlayer->topPos = inPlayer->bottomPos = inPlayer->topSize = inPlayer->bottomSize = 0;
        buf = AllocateOneRecordingBuffer();
        if (buf == NULL)
            return NULL;
        inPlayer->topFreeBuffer = buf;
        buf = AllocateOneRecordingBuffer();
        if (buf == NULL)
            return NULL;
        inPlayer->bottomFreeBuffer = buf;
        buf->next = inPlayer->topFreeBuffer;
    } else {
        if (inPlayer->topBuffer->next != NULL)
            return inPlayer->topBuffer->next;  /*  No need to allocate  */
        if (inPlayer->bottomFreeBuffer != NULL && inPlayer->bottomFreeBuffer->next != NULL) {
            buf = inPlayer->bottomFreeBuffer;
            inPlayer->bottomFreeBuffer = buf->next;
            memset(buf->data, 0, kMDRecordingBufferSize);
#if DEBUG
            if (gMDVerbose >= 2) {
                MDRecordingBuffer *b;
                fprintf(stderr, "%d %s[%d]: freeBuffer ", 2, __FILE__, __LINE__);
                for (b = inPlayer->bottomFreeBuffer; b != NULL; b = b->next)
                    fprintf(stderr, "%p -> ", b);
                fprintf(stderr, "(NULL)\n");
            }
#endif
        } else {
            buf = AllocateOneRecordingBuffer();
            if (buf == NULL)
                return NULL;
        }
        buf->next = NULL;
        inPlayer->topBuffer->next = buf;
        inPlayer->topBuffer = buf;
    }
    return inPlayer->topBuffer;
}

int
MDPlayerPutRecordingData(MDPlayer *inPlayer, MDTimeType timeStamp, int32_t size, const unsigned char *buf)
{
    unsigned char *op;
    MDRecordingEventHeader header;
    MDRecordingBuffer *topBuffer;
    int32_t topPos;
    int32_t nsize, n;

    if (inPlayer == NULL)
        return -1;
    if (inPlayer->topBuffer == NULL) {
        if (MDPlayerAllocateRecordingBuffer(inPlayer) == NULL)
            return -3;  /*  Out of memory  */
    }
    topBuffer = inPlayer->topBuffer;
    topPos = inPlayer->topPos;
    op = topBuffer->data + topPos;
    header.timeStamp = timeStamp;
    header.size = size;
    nsize = sizeof(header);
    n = topBuffer->size - topPos;
    if (n < nsize) {
        memcpy(op, (unsigned char *)(&header), n);
        nsize -= n;
        if (MDPlayerAllocateRecordingBuffer(inPlayer) == NULL)
            return -3;  /*  Out of memory  */
        topBuffer = topBuffer->next;
        topPos = 0;
        op = topBuffer->data;
    }
    if (nsize > 0) {
        memcpy(op, (unsigned char *)(&header) + sizeof(header) - nsize, nsize);
        topPos += nsize;
        op += nsize;
    }
    nsize = size;
    while (nsize > 0) {
        n = topBuffer->size - topPos;
        if (n <= 0) {
            if (MDPlayerAllocateRecordingBuffer(inPlayer) == NULL)
                return -3;  /*  Out of memory  */
            topBuffer = topBuffer->next;
            topPos = 0;
            n = topBuffer->size;
        }
        if (n > nsize)
            n = nsize;
        memcpy(topBuffer->data + topPos, buf, n);
        buf += n;
        nsize -= n;
        topPos += n;
    }
    inPlayer->topBuffer = topBuffer;
    inPlayer->topPos = topPos;
    inPlayer->topSize += header.size + sizeof(header);
    return 0;        
}

int
MDPlayerGetRecordingData(MDPlayer *inPlayer, MDTimeType *outTimeStamp, int32_t *outSize, unsigned char **outBuf, int32_t *outBufSize)
{
    /*  **outBuf and *outBufSize must contain valid values on calling, with a malloc'ed
        pointer in **outBuf and its size in *outBufSize. On return, both may be changed
        via realloc() when the buffer size is not sufficient  */
    unsigned char *ip, *op;
    MDRecordingEventHeader header;
    MDRecordingBuffer *bottomBuffer;
    int32_t bottomPos;
    int32_t size, n;
    if (inPlayer == NULL || inPlayer->bottomBuffer == NULL || inPlayer->bottomSize >= inPlayer->topSize)
        return -1;
    bottomBuffer = inPlayer->bottomBuffer;
    bottomPos = inPlayer->bottomPos;
    ip = bottomBuffer->data + bottomPos;
    size = sizeof(header);
    if (inPlayer->topSize - inPlayer->bottomSize <= size)
        return -2;	/* Internal inconsistency */
    n = bottomBuffer->size - bottomPos;
    if (n < size) {
        memcpy((unsigned char *)(&header), ip, n);
        size -= n;
        bottomBuffer = bottomBuffer->next;
        bottomPos = 0;
        ip = bottomBuffer->data;
    }
    if (size > 0) {
        memcpy((unsigned char *)(&header) + sizeof(header) - size, ip, size);
        bottomPos += size;
        ip += size;
    }
    size = header.size;
    if (inPlayer->topSize - inPlayer->bottomSize < size + sizeof(header))
        return -2;	/* Internal inconsistency */
    if (*outBuf == NULL) {
        n = (size + 4) / 4 * 4;
        *outBuf = (unsigned char *)malloc(n);
        if (*outBuf == NULL)
            return -3;  /*  Out of memory  */
        *outBufSize = n;
    } else if (*outBufSize <= size) {
        n = (size + 4) / 4 * 4;
        op = (unsigned char *)realloc(*outBuf, n);
        if (op == NULL)
            return -3;  /*  Out of memory  */
        *outBuf = op;
        *outBufSize = n;
    }
    op = *outBuf;
    while (size > 0) {
        n = bottomBuffer->size - bottomPos;
        if (n <= 0) {
            bottomBuffer = bottomBuffer->next;
            bottomPos = 0;
            n = bottomBuffer->size;
        }
        if (n > size)
            n = size;
        memcpy(op, bottomBuffer->data + bottomPos, n);
        op += n;
        size -= n;
        bottomPos += n;
    }
    if (bottomBuffer->size <= bottomPos) {
        bottomBuffer = bottomBuffer->next;
        bottomPos = 0;
    }
    if (inPlayer->bottomBuffer != bottomBuffer && inPlayer->topFreeBuffer != NULL) {
        /*  Put to the free block list for reuse  */
        MDRecordingBuffer *buf;
        buf = inPlayer->bottomBuffer;
        while (buf->next != NULL && buf->next != bottomBuffer)
            buf = buf->next;
        buf->next = NULL;
        inPlayer->topFreeBuffer->next = inPlayer->bottomBuffer;
        inPlayer->topFreeBuffer = buf;
#if DEBUG
        if (gMDVerbose >= 2) {
            fprintf(stderr, "%d %s[%d]: freeBuffer ", 2, __FILE__, __LINE__);
            for (buf = inPlayer->bottomFreeBuffer; buf != NULL; buf = buf->next)
                fprintf(stderr, "%p -> ", buf);
            fprintf(stderr, "(NULL)\n");
        }
#endif
    }
    inPlayer->bottomBuffer = bottomBuffer;
    inPlayer->bottomPos = bottomPos;
    inPlayer->bottomSize += header.size + sizeof(header);
    *outTimeStamp = header.timeStamp;
    *outSize = header.size;
#if DEBUG
	{
		if (sMIDIInputDump != NULL) {
			int i;
			fprintf(sMIDIInputDump, "-%qd ", (int64_t)*outTimeStamp);
			for (i = 0; i < header.size; i++) {
				fprintf(sMIDIInputDump, "%02x%c", (*outBuf)[i], (i == header.size - 1 ? '\n' : ' '));
			}
		}
	}
#endif
    return 0;
}

#if 0
static void
MySysexCompletionProc(MIDISysexSendRequest *request)
{
    request->bytesToSend = 0;
    *((unsigned char *)(request->completionRefCon)) = 0;
}
#endif

static int
ScheduleMIDIEventToDevice(int32_t dev, UInt64 timeStamp, int length, unsigned char *data)
{
    OSStatus sts;
    if (dev < 0 || dev >= sDeviceInfo.destNum)
        return 0;  /*  No output  */
    MDDeviceIDRecord *rp = &(sDeviceInfo.dest[dev]);
    if (rp->midiRec != NULL) {
        /*  Real MIDI device  */
        MDMIDIDeviceRecord *mrec = rp->midiRec;
        MIDIPacket *packet;
        packet = MIDIPacketListInit(&mrec->packetList);
        packet = MIDIPacketListAdd(&mrec->packetList, sizeof(mrec->packetList), packet, timeStamp, length, data);
        if (packet != NULL) {
            /*  Send packet  */
            sts = MIDISend(sMIDIOutputPortRef, mrec->eref, &mrec->packetList);
        } else sts = 1;
        if (sts != 0 && data[0] == 0xf0 && mrec->sysexRequest.complete != 0) {
            /*  Try to send sysex  */
            mrec->sysexRequest.destination = mrec->eref;
            mrec->sysexRequest.data = data;
            mrec->sysexRequest.bytesToSend = length;
            mrec->sysexRequest.complete = 0;
            mrec->sysexRequest.completionProc = NULL;
            mrec->sysexRequest.completionRefCon = NULL;
            sts = MIDISendSysex(&mrec->sysexRequest);
        }
        return (sts == 0 ? length : -1);
    } else if (rp->streamIndex >= 0) {
        MDAudioIOStreamInfo *ip = MDAudioGetIOStreamInfoAtIndex(rp->streamIndex);
//        printf("%lld %d %02x %02x...\n", ConvertHostTimeToMDTimeType(timeStamp), length, data[0], data[1]);
        sts = MDAudioScheduleMIDIToStream(ip, timeStamp, length, data, 0);
        if (sts != 0 && data[0] == 0xf0) {
            /*  Try to send sysex  */
            sts = MDAudioScheduleMIDIToStream(ip, timeStamp, length, data, 1);
        }
        return (sts == 0 ? length : -1);
    } else return 0;  /*  No output  */
}

static int
ScheduleMDEventToDevice(int32_t dev, UInt64 timeStamp, MDEvent *ep, int channel)
{
    unsigned char buf[4];
    unsigned char *p;
    int32_t len;
    if (MDIsSysexEvent(ep)) {
        p = MDGetMessagePtr(ep, &len);
    } else if (MDIsChannelEvent(ep)) {
        memset(buf, 0, 4);
        len = MDEventToMIDIMessage(ep, buf);
        buf[0] |= channel;
        p = buf;
    } else return 0;  /*  No output  */
    return ScheduleMIDIEventToDevice(dev, timeStamp, len, p);
}

static void
MyMIDIReadProc(const MIDIPacketList *pktlist, void *refCon, void *connRefCon)
{
    MDTimeType now, myTimeStamp;
    MIDIPacket *packet;
    unsigned char recordingFlag;
    int i, j, n;

//    dprintf(0, "MyMIDIReadProc invoked\n");
    if (sRecordingPlayer == NULL || sRecordingPlayer->isRecording == 0)
        recordingFlag = 0;
    else {
        recordingFlag = 1;
        now = GetHostTimeInMDTimeType() - sRecordingPlayer->startTime;
    }
    packet = (MIDIPacket *)pktlist->packet;
    for (i = 0; i < pktlist->numPackets; i++, packet = MIDIPacketNext(packet)) {
        if (sMIDIThruTranspose != 0) {
            /*  Transpose  */
            for (j = 0; j < packet->length; j++) {
                if (packet->data[j] >= 0x80 && packet->data[j] <= 0x9f) {
                    n = packet->data[j + 1] + sMIDIThruTranspose;
                    if (n >= 0 && n < 128)
                        packet->data[j + 1] = n;
                }
            }
        }
        if (recordingFlag) {
            if (packet->timeStamp != 0) {
                myTimeStamp = ConvertHostTimeToMDTimeType(packet->timeStamp) - sRecordingPlayer->startTime;
            } else myTimeStamp = now;
            n = MDPlayerPutRecordingData(sRecordingPlayer, myTimeStamp, (int32_t)(packet->length), (unsigned char *)(packet->data));
        }
        /*  Echo back  */
        if (sMIDIThruDevice >= 0) {
            if (sMIDIThruChannel >= 0 && sMIDIThruChannel < 16) {
                /*  Rechannelize status bytes  */
                for (j = 0; j < packet->length; j++) {
                    if (packet->data[j] >= 0x80 && packet->data[j] < 0xf0)
                        packet->data[j] = (packet->data[j] & 0xf0) | sMIDIThruChannel;
                }
            }
            ScheduleMIDIEventToDevice(sMIDIThruDevice, packet->timeStamp, packet->length, packet->data);
        }
    }
}

static void
RegisterEventInNoteOffTrack(MDDestinationInfo *info, const MDEvent *ep)
{
	MDEvent *ep0;
	MDPointerJumpToTick(info->noteOffPtr, MDGetTick(ep) + 1);
	MDPointerInsertAnEvent(info->noteOffPtr, ep);
	MDPointerSetPosition(info->noteOffPtr, 0);
	if ((ep0 = MDPointerCurrent(info->noteOffPtr)) != NULL)
		info->noteOffTick = MDGetTick(ep0);
	else info->noteOffTick = kMDMaxTick;
}

static void
PrepareMetronomeForTick(MDPlayer *inPlayer, MDTickType inTick)
{
	MDEvent *ep;
	int32_t timebase = MDSequenceGetTimebase(inPlayer->sequence);
	MDTickType t, t0;
    int32_t beat, bar;
	MDCalibratorJumpToTick(inPlayer->calib, inTick);
	ep = MDCalibratorGetEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
    MDEventCalculateMetronomeBarAndBeat(ep, timebase, &bar, &beat);
    inPlayer->metronomeBeat = beat;
    inPlayer->metronomeBar = bar;
    t = (ep == NULL ? 0 : MDGetTick(ep));
/*	if (ep == NULL) {
		t = 0;
		inPlayer->metronomeBeat = timebase;
		inPlayer->metronomeBar = timebase * 4;
	} else {
		const unsigned char *p = MDGetMetaDataPtr(ep);
		t = MDGetTick(ep);
		inPlayer->metronomeBeat = timebase * p[2] / 24;
		inPlayer->metronomeBar = timebase * p[0] * 4 / (1 << p[1]);
        if (inPlayer->metronomeBar < timebase / 64)
            inPlayer->metronomeBar = timebase;
        if (inPlayer->metronomeBeat < timebase / 64)
            inPlayer->metronomeBeat = inPlayer->metronomeBar;
	} */
	inPlayer->nextMetronomeBar = t + (inTick - t + inPlayer->metronomeBar - 1) / inPlayer->metronomeBar * inPlayer->metronomeBar;
	t0 = inPlayer->nextMetronomeBar;
	if (t0 > inTick)
		t0 -= inPlayer->metronomeBar;
	inPlayer->nextMetronomeBeat = t0 + (inTick - t0 + inPlayer->metronomeBeat - 1) / inPlayer->metronomeBeat * inPlayer->metronomeBeat;
	if (inPlayer->nextMetronomeBeat > inPlayer->nextMetronomeBar)
		inPlayer->nextMetronomeBeat = inPlayer->nextMetronomeBar;
	ep = MDCalibratorGetNextEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
	if (ep == NULL)
		inPlayer->nextTimeSignature = kMDMaxTick;
	else inPlayer->nextTimeSignature = MDGetTick(ep);
}

/*  Send MIDI events before prefetch_tick to their destinations  */
/*  foreach destination {
      while true {
        get_one_event # metronome, internal note-off, or MIDI event
        if beyond stop_tick {
          set next_tick
          break
        }
        if beyond prefetch_tick { 
          #  stop_tick should be handled by the caller as prefetch_tick
          set next_tick
          break  #  to next destination
        } else if cannot schedule {
          set next_tick
          break  #  to next destination
        }
     }
   }
*/

enum {
    kNoScheduleType = 0,
    kMetronomeScheduleType,
    kNoteOffScheduleType,
    kTrackScheduleType,
    kMutedScheduleType
};

static int32_t
SendMIDIEventsBeforeTick(MDPlayer *inPlayer, MDTickType now_tick, MDTickType prefetch_tick, MDTickType *outNextTick)
{
    int n, bytesToSend = 0;
    MDTickType sequenceDuration = MDSequenceGetDuration(inPlayer->sequence);
    MDTickType nextTick = kMDMaxTick;

    for (n = 0; n < inPlayer->destNum; n++) {
        MDDestinationInfo *info;
        MDTickType currentTick;
        info = inPlayer->destInfo[n];
        while (1) {
            unsigned char scheduleType = kTrackScheduleType;
            MDEvent *ep, metEvent, offEvent;
            unsigned char channel, isBell;
            
            currentTick = info->currentTick;
            if (info->currentEp == NULL) {
                /*  No event  */
                currentTick = kMDMaxTick;
                scheduleType = kNoScheduleType;
            } else {
                MDTrackAttribute attr;
                attr = MDTrackGetAttribute(info->currentTrack);
                if (attr & (kMDTrackAttributeMute | kMDTrackAttributeMuteBySolo))
                    scheduleType = kMutedScheduleType;
            }

            /*  Registered note-off?  */
            if (info->noteOffTick <= currentTick) {
                scheduleType = kNoteOffScheduleType;
                currentTick = info->noteOffTick;
            }
            
            /*  Metronome device?  */
            if (gMetronomeInfo.dev == info->dev) {
                if (gMetronomeInfo.enableWhenPlay || (gMetronomeInfo.enableWhenRecord && inPlayer->isRecording)) {
                    MDTickType metroTick;
                    if (inPlayer->nextMetronomeBeat < 0) {
                        PrepareMetronomeForTick(inPlayer, now_tick);
                    }
                    metroTick = inPlayer->nextMetronomeBeat;
                    if (!inPlayer->isRecording && metroTick >= sequenceDuration) {
                        /* Metronome will not ring after sequence duration
                           unless MIDI recording is on  */
                        metroTick = kMDMaxTick;
                    }
                    if (metroTick <= currentTick) {
                        /*  Metronome event is earlier  */
                        scheduleType = kMetronomeScheduleType;
                        currentTick = metroTick;
                        isBell = (metroTick == inPlayer->nextMetronomeBar);
                    }
                }
            }

            /*  Out of range?  */
            if (currentTick >= prefetch_tick)
                break;

            /*  Prepare MIDI event  */
            if (scheduleType == kMetronomeScheduleType) {
                MDTickType metDuration;
                MDEventInit(&metEvent);
                MDSetKind(&metEvent, kMDEventNote);
                MDSetCode(&metEvent, (isBell ? gMetronomeInfo.note1 : gMetronomeInfo.note2));
                MDSetNoteOnVelocity(&metEvent, (isBell ? gMetronomeInfo.vel1 : gMetronomeInfo.vel2));
                MDSetNoteOffVelocity(&metEvent, 0);
                MDSetTick(&metEvent, currentTick);
                MDSetChannel(&metEvent, gMetronomeInfo.channel & 15);
                metDuration = MDCalibratorTimeToTick(inPlayer->calib, MDCalibratorTickToTime(inPlayer->calib, currentTick) + gMetronomeInfo.duration) - currentTick;
                MDSetDuration(&metEvent, metDuration);
                ep = &metEvent;
                channel = gMetronomeInfo.channel & 15;
            //    printf("%ld %c\n", currentTick, (isBell ? '*' : ' '));
            } else if (scheduleType == kNoteOffScheduleType) {
                ep = MDPointerCurrent(info->noteOffPtr);
                channel = MDGetChannel(ep);
            } else if (scheduleType == kTrackScheduleType) {
                ep = info->currentEp;
                channel = MDTrackGetTrackChannel(info->currentTrack);
                if (MDIsMetaEvent(ep)) {
                    ep = NULL;
                }
            } else ep = NULL;
            
            if (ep != NULL) {
                int len;
                MDTimeType scheduleTime = MDCalibratorTickToTime(inPlayer->calib, currentTick);
                UInt64 timeStamp = ConvertMDTimeTypeToHostTime(scheduleTime + inPlayer->startTime);
                /*  Schedule the MIDI event to the device  */
                len = ScheduleMDEventToDevice(info->dev, timeStamp, ep, channel);
                if (len < 0) {
                    /*  Unsuccessful: break loop and continue to the next destination  */
                    break;
                }
                bytesToSend += len;
                if (scheduleType == kMetronomeScheduleType) {
                    /*  Proceed to the next metronome event  */
                    if (inPlayer->nextMetronomeBar == inPlayer->nextMetronomeBeat)
                        inPlayer->nextMetronomeBar += inPlayer->metronomeBar;
                    inPlayer->nextMetronomeBeat += inPlayer->metronomeBeat;
                    if (inPlayer->nextMetronomeBeat > inPlayer->nextMetronomeBar)
                        inPlayer->nextMetronomeBeat = inPlayer->nextMetronomeBar;
                    if (inPlayer->nextMetronomeBar >= inPlayer->nextTimeSignature) {
                        PrepareMetronomeForTick(inPlayer, inPlayer->nextMetronomeBeat);
                    }
                } else if (scheduleType == kNoteOffScheduleType) {
                    /*  Unregister this internal-note-off  */
                    MDPointerDeleteAnEvent(info->noteOffPtr, NULL);
                    MDPointerSetPosition(info->noteOffPtr, 0);
                    if ((ep = MDPointerCurrent(info->noteOffPtr)) != NULL)
                        info->noteOffTick = MDGetTick(ep);
                    else info->noteOffTick = kMDMaxTick;
                } else if (MDGetKind(ep) == kMDEventNote) {
                    /*  Register an internal-note-off  */
                    MDSetKind(&offEvent, kMDEventInternalNoteOff);
                    MDSetCode(&offEvent, MDGetCode(ep));
                    MDSetChannel(&offEvent, channel);
                    MDSetNoteOffVelocity(&offEvent, MDGetNoteOffVelocity(ep));
                    MDSetTick(&offEvent, MDGetTick(ep) + MDGetDuration(ep));
                    RegisterEventInNoteOffTrack(info, &offEvent);
                }
            }
            if (scheduleType == kTrackScheduleType || scheduleType == kMutedScheduleType) {
                /*  Proceed to next event  */
                info->currentEp = MDTrackMergerForward(info->merger, &(info->currentTrack));
                if (info->currentEp != NULL)
                    info->currentTick = MDGetTick(info->currentEp);
                else info->currentTick = kMDMaxTick;
            }
        }
        /*  At this point, currentTick is 'the tick of the next event'
            (if no more event are present, then kMDMaxTick)  */
        if (currentTick < nextTick)
            nextTick = currentTick;
    }
    if (nextTick == kMDMaxTick) {
        if (prefetch_tick < sequenceDuration) {
            /*  If no more event is present but sequence duration is not reached  */
            nextTick = sequenceDuration;
        } else if (inPlayer->isRecording) {
            /*  If no more event is present but is recording MIDI, then continue playing  */
            nextTick = prefetch_tick + 1;
        }
    }
    *outNextTick = nextTick;
    return bytesToSend;
}

static int32_t
MyTimerFunc(MDPlayer *player)
{
	MDTimeType now_time, last_time;
    MDTimeType time_to_wait;
	MDTickType now_tick, prefetch_tick, tick;
	MDSequence *sequence;
	int32_t n;
	
	if (player == NULL)
		return -1;

	sequence = player->sequence;
	
	now_time = GetHostTimeInMDTimeType() - player->startTime;
    if (now_time < player->countOffEndTime) {
        /*  During count-off  */
        MDTimeType time1, time2;
        if (player->countOffNextRing < player->countOffEndTime && player->countOffNextRing <  now_time + kMDPlayerPrefetchInterval) {
            /*  Ring the metronome  */
            int isBell = 0;
            if (player->countOffBar > 0 && (player->countOffNextRing - player->countOffFirstRing) % player->countOffBar == 0)
                isBell = 1;
            MDPlayerRingMetronomeClick(player, player->countOffNextRing, isBell);
            /*  Next metronome  */
            time1 = player->countOffNextRing + player->countOffBeat;
            if (player->countOffBar > 0) {
                time2 = ((player->countOffNextRing - player->countOffFirstRing) / player->countOffBar + 1) * player->countOffBar + player->countOffFirstRing;
                if (time2 < time1)
                    time1 = time2;
            }
            player->countOffNextRing = time1;
        }
        time1 = player->countOffNextRing - now_time;
        time2 = player->countOffEndTime - now_time;
        time_to_wait = (time1 < time2 ? time1 : time2);
        if (time_to_wait < kMDPlayerMinimumInterval)
            time_to_wait = kMDPlayerMinimumInterval;
        return (int32_t)time_to_wait;
    }
    player->time = now_time;
	now_tick = MDCalibratorTimeToTick(player->calib, now_time);
	prefetch_tick = MDCalibratorTimeToTick(player->calib, now_time + kMDPlayerPrefetchInterval);
	last_time = 0;
	
    if (MDSequenceTryLock(sequence) == 0) {
    /*    if (now_tick >= player->recordingStopTick) {
            if (player->isRecording)
                MDPlayerStopRecording(player);
            if (MDAudioIsRecording())
                MDAudioStopRecording();
            player->recordingStopTick = kMDMaxTick;
        } */
        n = SendMIDIEventsBeforeTick(player, now_tick, prefetch_tick, &tick);
    //    printf("now_tick = %ld tick = %ld\n", now_tick, tick);
        if (tick >= kMDMaxTick) {
            player->status = kMDPlayer_exhausted;
            time_to_wait = -1;
        } else {
            time_to_wait = now_time - MDCalibratorTickToTime(player->calib, tick);
            if (time_to_wait > kMDPlayerPrefetchInterval)
                time_to_wait = kMDPlayerPrefetchInterval;
            else if (time_to_wait < kMDPlayerMinimumInterval)
                time_to_wait = kMDPlayerMinimumInterval;
        }
		MDSequenceUnlock(sequence);
    } else {
        n = 0;
        time_to_wait = kMDPlayerPrefetchInterval;
    }
    return (int32_t)time_to_wait;
    
#if 0
	player->time = now_time;
	if (tick >= kMDMaxTick && !player->isRecording && !MDAudioIsRecording()) {
		player->status = kMDPlayer_exhausted;
		//	player->time = MDCalibratorTickToTime(player->calib, MDSequenceGetDuration(MDMergerGetSequence(player->merger)));
		if (tick >= kMDMaxTick)
			tick = MDSequenceGetDuration(sequence);
		player->time = MDCalibratorTickToTime(player->calib, tick);
		return -1;
	} else {
        if (now_tick >= player->recordingStopTick) {
            if (player->isRecording)
                MDPlayerStopRecording(player);
            if (MDAudioIsRecording())
                MDAudioStopRecording();
            player->recordingStopTick = kMDMaxTick;
        }
		if (tick >= kMDMaxTick && player->nextMetronomeBeat < tick)
			tick = player->nextMetronomeBeat;
		next_time = MDCalibratorTickToTime(player->calib, tick + 1);
		next_time -= (now_time + kMDPlayerPrefetchInterval);
		if (next_time < kMDPlayerMinimumInterval)
			next_time = kMDPlayerMinimumInterval;
		if (next_time < last_time - now_time)
			next_time = last_time - now_time;
		return (int32_t)next_time;
	}
#endif
}

#if !USE_TIME_MANAGER
void *
MyThreadFunc(void *param)
{
	MDPlayer *player = (MDPlayer *)param;
	int32_t time_to_wait;
	while ((player->status == kMDPlayer_playing || (player->status == kMDPlayer_exhausted && player->isRecording)) && player->shouldTerminate == 0) {
		time_to_wait = MyTimerFunc(player);
		if (time_to_wait < 0)
			break;
		while (time_to_wait > 0 && player->shouldTerminate == 0) {
			/*  Check every 100ms whether the player should terminate  */
			int32_t n = (time_to_wait > kMDPlayerMaximumInterval * 2 ? kMDPlayerMaximumInterval : time_to_wait);
			my_usleep(n);
			time_to_wait -= n;
		}
	}
	return NULL;
}

#else
static void
MyTimerCallback(TMTaskPtr tmTaskPtr)
{
	int32_t time_to_wait;
	time_to_wait = MyTimerFunc(((MyTMTask *)tmTaskPtr)->player);
	if (time_to_wait > 0)
	PrimeTimeTask((QElemPtr)tmTaskPtr, -time_to_wait);
}
#endif

static void
StopSoundInAllTracks(MDPlayer *inPlayer)
{
	int n, num;
	MDDestinationInfo *info;
    MDDeviceIDRecord *rec;
    MDAudioIOStreamInfo *ip;
	unsigned char buf[6];

	if (inPlayer == NULL)
		return;

	/*  Dispose the already scheduled MIDI events  */
	for (n = inPlayer->destNum - 1; n >= 0; n--) {
        if (inPlayer->destInfo[n] != NULL) {
            rec = &sDeviceInfo.dest[inPlayer->destInfo[n]->dev];
            if (rec->midiRec != NULL) {
                MIDIFlushOutput(rec->midiRec->eref);
            } else if (rec->streamIndex >= 0) {
                ip = MDAudioGetIOStreamInfoAtIndex(rec->streamIndex);
                ip->requestFlush = 1;
            }
        }
    }
	
    /*  Wait until all requestFlush are processed  */
    while (1) {
        for (n = inPlayer->destNum - 1; n >= 0; n--) {
            if (inPlayer->destInfo[n] != NULL) {
                rec = &sDeviceInfo.dest[inPlayer->destInfo[n]->dev];
                if (rec->midiRec == NULL && rec->streamIndex >= 0) {
                    ip = MDAudioGetIOStreamInfoAtIndex(rec->streamIndex);
                    if (ip->requestFlush)
                        break;
                }
            }
        }
        if (n < 0)
            break;
        my_usleep(10000);
    }
    
	/*  Dispose the pending note-offs  */
    for (n = inPlayer->destNum - 1; n >= 0; n--) {
        MDTrack *track;
        info = inPlayer->destInfo[n];
        if (info == NULL)
            continue;
        if (info->noteOff != NULL) {
            MDTrackClear(info->noteOff);
            info->noteOffTick = kMDMaxTick;
        }
        
        /*  Send AllNoteOff (Bn 7B 00), AllSoundOff (Bn 78 00), ResetAllControllers
            (Bn 79 00) to all tracks  */
        for (num = 0; (track = MDTrackMergerGetTrack(info->merger, num)) != NULL; num++) {
            int channel = MDTrackGetTrackChannel(track);
            buf[0] = 0xB0 + channel;
            buf[1] = 0x7B;
            buf[2] = 0;
            ScheduleMIDIEventToDevice(info->dev, 0, 3, buf);
            buf[0] = 0xB0 + channel;
            buf[1] = 0x78;
            buf[2] = 0;
            ScheduleMIDIEventToDevice(info->dev, 0, 3, buf);
            buf[0] = 0xB0 + channel;
            buf[1] = 0x79;
            buf[2] = 0;
            ScheduleMIDIEventToDevice(info->dev, 0, 3, buf);
        }
    }
}

int
MDPlayerSendRawMIDI(MDPlayer *inPlayer, const unsigned char *p, int size, int destDevice, MDTimeType scheduledTime)
{
    MDDeviceIDRecord *rp;
    UInt64 timeStamp;
    
    if (destDevice < 0 || destDevice >= sDeviceInfo.destNum)
		return -1;
    rp = &(sDeviceInfo.dest[destDevice]);
    if (inPlayer != NULL && scheduledTime + inPlayer->startTime >= 0)
        timeStamp = ConvertMDTimeTypeToHostTime(scheduledTime + inPlayer->startTime);
    else if (scheduledTime >= 0)
        timeStamp = ConvertMDTimeTypeToHostTime(scheduledTime);
    else timeStamp = 0;
    return ScheduleMIDIEventToDevice(destDevice, timeStamp, size, (unsigned char *)p);
}

void
MDPlayerRingMetronomeClick(MDPlayer *inPlayer, MDTimeType atTime, int isPrincipal)
{
	unsigned char buf[4];
	buf[0] = 0x90 + (gMetronomeInfo.channel & 15);
	buf[1] = (isPrincipal ? gMetronomeInfo.note1 : gMetronomeInfo.note2);
	buf[2] = (isPrincipal ? gMetronomeInfo.vel1 : gMetronomeInfo.vel2);
	if (atTime == 0) {
		atTime = GetHostTimeInMDTimeType();
		if (inPlayer != NULL)
			atTime -= inPlayer->startTime;
	}
	MDPlayerSendRawMIDI(inPlayer, buf, 3, gMetronomeInfo.dev, atTime);
	buf[2] = 0;
	MDPlayerSendRawMIDI(inPlayer, buf, 3, gMetronomeInfo.dev, atTime + gMetronomeInfo.duration);
}

#pragma mark ====== MDPlayer Functions ======

/* --------------------------------------
	･ MDPlayerNew
   -------------------------------------- */
MDPlayer *
MDPlayerNew(MDSequence *inSequence)
{
	MDPlayer *player = (MDPlayer *)malloc(sizeof(MDPlayer));
	if (player != NULL) {
		memset(player, 0, sizeof(MDPlayer));
		player->refCount = 1;
        player->sequence = inSequence;
        MDSequenceRetain(inSequence);
		player->calib = MDCalibratorNew(inSequence, NULL, kMDEventTempo, -1);
		if (player->calib == NULL)
            goto error;
		MDCalibratorAppend(player->calib, NULL, kMDEventTimeSignature, -1);

		player->status = kMDPlayer_idle;
		player->time = 0;
		player->startTime = 0;
		player->recordingStopTick = kMDMaxTick;

		player->destInfo = NULL;
		player->destNum = 0;
	/*	player->destIndex = NULL;
        player->destChannel = NULL;
        player->trackAttr = NULL; */

        if (MDPlayerAllocateRecordingBuffer(player) == NULL)
            goto error;
    
        player->tempStorage = (unsigned char *)malloc(256);
        if (player->tempStorage == NULL)
            goto error;
        player->tempStorageSize = 256;
		
	}
	return player;

    error:
    MDPlayerReleaseRecordingBuffer(player);
    if (player->tempStorage != NULL)
        free(player->tempStorage);
    if (player->calib != NULL)
        MDCalibratorRelease(player->calib);
    if (player->sequence != NULL)
        MDSequenceRelease(player->sequence);
    free(player);
    return NULL;
}

/* --------------------------------------
	･ MDPlayerRetain
   -------------------------------------- */
void
MDPlayerRetain(MDPlayer *inPlayer)
{
	if (inPlayer != NULL)
		inPlayer->refCount++;
}

/* --------------------------------------
	･ MDPlayerRelease
   -------------------------------------- */
void
MDPlayerRelease(MDPlayer *inPlayer)
{
	int32_t num;
	if (inPlayer != NULL) {
		if (--inPlayer->refCount == 0) {
			if (inPlayer->status == kMDPlayer_playing || inPlayer->status == kMDPlayer_exhausted)
				MDPlayerStop(inPlayer);
			if (inPlayer->destInfo != NULL) {
				for (num = 0; num < inPlayer->destNum; num++)
					MDPlayerReleaseDestinationInfo(inPlayer->destInfo[num]);
				free(inPlayer->destInfo);
			}
            if (inPlayer->tempStorage != NULL)
                free(inPlayer->tempStorage);
       /*     if (inPlayer->trackAttr != NULL)
                free(inPlayer->trackAttr);
            if (inPlayer->destChannel != NULL)
                free(inPlayer->destChannel);
			if (inPlayer->destIndex != NULL)
				free(inPlayer->destIndex); */
			if (inPlayer->calib != NULL)
				MDCalibratorRelease(inPlayer->calib);
            if (inPlayer->sequence != NULL)
                MDSequenceRelease(inPlayer->sequence);
            MDPlayerReleaseRecordingBuffer(inPlayer);
			free(inPlayer);
		}
	}
}

/* --------------------------------------
	･ MDPlayerSetSequence
   -------------------------------------- */
MDStatus
MDPlayerSetSequence(MDPlayer *inPlayer, MDSequence *inSequence)
{
    if (inPlayer != NULL) {
		MDCalibrator *calib;
		if (inPlayer->status == kMDPlayer_playing || inPlayer->status == kMDPlayer_exhausted)
			MDPlayerStop(inPlayer);
		calib = MDCalibratorNew(inSequence, NULL, kMDEventTempo, -1);
		if (calib == NULL)
			return kMDErrorOutOfMemory;
		MDCalibratorRelease(inPlayer->calib);
		inPlayer->calib = calib;
        MDSequenceRelease(inPlayer->sequence);
        inPlayer->sequence = inSequence;
        MDSequenceRetain(inSequence);
        inPlayer->time = 0;
        inPlayer->startTime = 0;
	}
    return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerGetAudioPlayer
   -------------------------------------- */
MDAudio *
MDPlayerGetAudioPlayer(MDPlayer *inPlayer)
{
	if (inPlayer == NULL)
		return NULL;
	else return inPlayer->audio;
}

/* --------------------------------------
	･ MDPlayerRefreshTrackDestinations
   -------------------------------------- */
MDStatus
MDPlayerRefreshTrackDestinations(MDPlayer *inPlayer)
{
    MDSequence *sequence;
    int32_t n, num, i, dev;
    int32_t *temp;

    /*  TODO: we need to rewrite all here!  */
    if (inPlayer == NULL || (sequence = inPlayer->sequence) == NULL)
        return kMDNoError;
	
    num = MDSequenceGetNumberOfTracks(sequence);
//	inPlayer->trackNum = num;
//    inPlayer->destIndex = (int32_t *)re_malloc(inPlayer->destIndex, num * sizeof(int32_t));
//    if (inPlayer->destIndex == NULL)
//        return kMDErrorOutOfMemory;
//    inPlayer->destChannel = (unsigned char *)re_malloc(inPlayer->destChannel, num * sizeof(unsigned char));
//    if (inPlayer->destChannel == NULL)
//        return kMDErrorOutOfMemory;
//    inPlayer->trackAttr = (MDTrackAttribute *)re_malloc(inPlayer->trackAttr, num * sizeof(MDTrackAttribute));
//    if (inPlayer->trackAttr == NULL)
//        return kMDErrorOutOfMemory;

    temp = (int32_t *)malloc((num + 1) * sizeof(int32_t));
    if (temp == NULL)
        return kMDErrorOutOfMemory;

//	for (i = 0; i < inPlayer->destNum; i++)
//        temp[i] = inPlayer->destInfo[i]->dev;
//    origDestNum = inPlayer->destNum;

	MDSequenceLock(sequence);
    
    /*  Dispose previous destInfo[]  */
    if (inPlayer->destInfo != NULL) {
        for (i = 0; i < inPlayer->destNum; i++)
            MDPlayerReleaseDestinationInfo(inPlayer->destInfo[i]);
        free(inPlayer->destInfo);
    }
    
    /*  Allocate destInfo  */
    inPlayer->destInfo = (MDDestinationInfo **)malloc((num + 1) * sizeof(MDDestinationInfo *));
    if (inPlayer->destInfo == NULL)
        return kMDErrorOutOfMemory;
    memset(inPlayer->destInfo, 0, num * sizeof(MDDestinationInfo *));
    inPlayer->destNum = 0;

    /*  Initialize MDDestinationInfo for necessary destinations  */
    /*  (each track and metronome)  */
    for (n = 0; n <= num; n++) {
        MDTrack *track;
        MDDestinationInfo *info;
        char name1[256];
        if (n == num) {
            dev = gMetronomeInfo.dev;
        } else {
            track = MDSequenceGetTrack(sequence, n);
            if (track == NULL)
                continue;
            MDTrackGetDeviceName(track, name1, sizeof name1);
            dev = MDPlayerGetDestinationNumberFromName(name1);
        }
        if (dev >= 0) {
            for (i = 0; i < inPlayer->destNum; i++) {
                if (inPlayer->destInfo[i]->dev == dev)
                    break;
            }
            if (i == inPlayer->destNum) {
                /*  New device  */
                inPlayer->destInfo[i] = MDPlayerNewDestinationInfo(dev);
                inPlayer->destNum++;
            }
            /*  Add this track to the destination info  */
            info = inPlayer->destInfo[i];
            if (info->merger == NULL) {
                info->merger = MDTrackMergerNew();
                if (info->merger == NULL)
                    return kMDErrorOutOfMemory;
            }
            if (n < num && MDTrackMergerAddTrack(info->merger, track) < 0)
                return kMDErrorOutOfMemory;
            info->noteOff = MDTrackNew();
            info->noteOffPtr = MDPointerNew(info->noteOff);
            info->noteOffTick = kMDMaxTick;
        }
    }
    MDPlayerJumpToTick(inPlayer, 0);

    MDSequenceUnlock(sequence);
    
    return kMDNoError;

#if 0
    /*  Update destIndex[] and destChannel[] */
    for (n = 0; n < num; n++) {
        MDTrack *track;
        char name1[256];
        track = MDSequenceGetTrack(sequence, n);
        i = -1;
        if (track != NULL) {
            /*  Look up the device name  */
            MDTrackGetDeviceName(track, name1, sizeof name1);
            dev = MDPlayerGetDestinationNumberFromName(name1);
		/*	dev = MDTrackGetDevice(track); */
            /*  Is it already used?  */
            if (dev >= 0) {
                for (i = 0; i < inPlayer->destNum; i++) {
                    if (temp[i] == dev)
                        break;
                }
                if (i == inPlayer->destNum) {
                    /*  new device  */
                    temp[i] = dev;
                    inPlayer->destNum++;
                }
            }
        }
        inPlayer->destIndex[n] = i;
        inPlayer->destChannel[n] = MDTrackGetTrackChannel(track);
        inPlayer->trackAttr[n] = MDTrackGetAttribute(track);
        dprintf(2, "%s%d%s", (n==0?"trackAttr={":""), inPlayer->trackAttr[n], (n==num-1?"}\n":","));
    }
	/*  Register device for metronome output  */
	if (gMetronomeInfo.enableWhenPlay || gMetronomeInfo.enableWhenRecord) {
		for (i = 0; i < inPlayer->destNum; i++) {
			if (temp[i] == gMetronomeInfo.dev)
				break;
		}
		if (i == inPlayer->destNum) {
			temp[i] = gMetronomeInfo.dev;
			inPlayer->destNum++;
		}
	}
#endif
}

/* --------------------------------------
	･ MDPlayerJumpToTick
   -------------------------------------- */
MDStatus
MDPlayerJumpToTick(MDPlayer *inPlayer, MDTickType inTick)
{
    int i;
    MDCalibratorJumpToTick(inPlayer->calib, inTick);
    for (i = 0; i < inPlayer->destNum; i++) {
        MDDestinationInfo *info = inPlayer->destInfo[i];
        info->currentEp = MDTrackMergerJumpToTick(info->merger, inTick, &info->currentTrack);
        if (info->currentEp != NULL)
            info->currentTick = MDGetTick(info->currentEp);
        else info->currentTick = kMDMaxTick;
        MDTrackClear(info->noteOff);
        MDPointerSetPosition(info->noteOffPtr, 0);
        info->noteOffTick = kMDMaxTick;
    }
    inPlayer->lastTick = inTick;
	inPlayer->time = MDCalibratorTickToTime(inPlayer->calib, inTick);
	inPlayer->status = kMDPlayer_ready;
	return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerPreroll
   -------------------------------------- */
MDStatus
MDPlayerPreroll(MDPlayer *inPlayer, MDTickType inTick, int backtrack)
{
/*	int32_t i, num, dev, *temp; */
/*	MDSequence *sequence; */
    MDStatus sts;
	if (inPlayer != NULL && inPlayer->sequence != NULL) {
        sts = MDPlayerRefreshTrackDestinations(inPlayer);
		MDPlayerJumpToTick(inPlayer, inTick);
        if (sts != kMDNoError)
            return sts;
        /*  Backtrack earlier events  */
        if (inTick > 0 && backtrack) {
            static int32_t sEventType[] = {
                kMDEventSysex, kMDEventSysexCont, kMDEventKeyPres,
                kMDEventProgram,
                ((0 << 16) + kMDEventControl), ((6 << 16) + kMDEventControl),
                ((32 << 16) + kMDEventControl), ((100 << 16) + kMDEventControl),
                ((101 << 16) + kMDEventControl), ((98 << 16) + kMDEventControl),
                ((99 << 16) + kMDEventControl),
                -1 };
            static int32_t sEventLastOnly[] = {
                kMDEventPitchBend, kMDEventChanPres,
                ((0xffff << 16) | kMDEventControl),
                -1 };
            MDPlayerBacktrackEvents(inPlayer, inTick, sEventType, sEventLastOnly);
        }
        
        /*  Prepare metronome  */
        PrepareMetronomeForTick(inPlayer, inTick);
        inPlayer->status = kMDPlayer_suspended;
	}
	return kMDNoError;
}


/* --------------------------------------
	･ MDPlayerStart
   -------------------------------------- */
MDStatus
MDPlayerStart(MDPlayer *inPlayer)
{
	int status;
/*	MDSequence *sequence; */

	if (inPlayer == NULL || inPlayer->sequence == NULL)
		return kMDNoError;
	if (inPlayer->status == kMDPlayer_playing)
		return kMDNoError;

	if (inPlayer->status != kMDPlayer_suspended)
		MDPlayerPreroll(inPlayer, MDCalibratorTimeToTick(inPlayer->calib, inPlayer->time), 0);
	
	if (MDSequenceCreateMutex(inPlayer->sequence))
		return kMDErrorOnSequenceMutex;
	
	inPlayer->startTime = GetHostTimeInMDTimeType() - inPlayer->time;
    inPlayer->countOffEndTime = inPlayer->time;
    if (inPlayer->isRecording && inPlayer->countOffDuration > 0) {
        /*  Look for the earliest metronome tick after start time  */
        int32_t bar, beat, barnum, beatnum;
        MDTickType dtick;
        MDTickType tick = MDCalibratorTimeToTick(inPlayer->calib, inPlayer->time);
        MDEvent *ep = MDCalibratorGetEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
        MDTickType sigtick = (ep == NULL ? 0 : MDGetTick(ep));
        int32_t timebase = MDSequenceGetTimebase(inPlayer->sequence);
        inPlayer->startTime += inPlayer->countOffDuration;
        MDEventCalculateMetronomeBarAndBeat(ep, timebase, &bar, &beat);
        tick -= sigtick;
        barnum = tick / bar;
        dtick = tick % bar;
        beatnum = dtick / beat;
        dtick = dtick % beat;
        if (dtick > 0) {
            beatnum++;
            if (beatnum * beat >= bar) {
                barnum++;
                beatnum = 0;
            }
        }
        tick = sigtick + barnum * bar;
        inPlayer->countOffFirstRing = MDCalibratorTickToTime(inPlayer->calib, tick) - inPlayer->countOffDuration;
        tick += beatnum * beat;
        inPlayer->countOffNextRing = MDCalibratorTickToTime(inPlayer->calib, tick) - inPlayer->countOffDuration;
    }
	inPlayer->status = kMDPlayer_playing;
	inPlayer->shouldTerminate = 0;
    
#if !USE_TIME_MANAGER
	status = pthread_create(&inPlayer->playThread, NULL, MyThreadFunc, inPlayer);
	if (status != 0)
		return kMDErrorCannotStartPlaying;
#else
	{
		OSStatus err;
		inPlayer->myTMTask.tmTask.tmAddr = NewTimerUPP(MyTimerCallback);
		inPlayer->myTMTask.tmTask.tmCount = 0;
		inPlayer->myTMTask.tmTask.tmWakeUp = 0;
		inPlayer->myTMTask.tmTask.tmReserved = 0;
		inPlayer->myTMTask.player = inPlayer;
		
		err = InstallXTimeTask((QElemPtr)&(inPlayer->myTMTask));
		err = PrimeTimeTask((QElemPtr)&(inPlayer->myTMTask), -100);
	}
#endif

	return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerStop
 -------------------------------------- */
MDStatus
MDPlayerStop(MDPlayer *inPlayer)
{
    if (inPlayer == NULL || inPlayer->sequence == NULL)
        return kMDNoError;
    
    if (inPlayer->status == kMDPlayer_suspended) {
        inPlayer->recordingStopTick = kMDMaxTick;
        inPlayer->status = kMDPlayer_ready;
        return kMDNoError;
    }
    if (inPlayer->status != kMDPlayer_playing && inPlayer->status != kMDPlayer_exhausted)
        return kMDNoError;
    
    /*  Stop MIDI recording  */
    MDPlayerStopRecording(inPlayer);
    
    /*  Stop Audio Processing  */
    /*	MDAudioStop(inPlayer->audio); */
    
    /*    for (i = MIDIGetNumberOfSources() - 1; i >= 0; i--) {
     MIDIPortDisconnectSource(sMIDIInputPortRef, MIDIGetSource(i));
     } */
    
#if !USE_TIME_MANAGER
    inPlayer->shouldTerminate = 1;
    pthread_join(inPlayer->playThread, NULL);  /*  Wait for the playing thread to terminate  */
#else
    {
        OSStatus err = RemoveTimeTask((QElemPtr)&(inPlayer->myTMTask));
        DisposeTimerUPP(inPlayer->myTMTask.tmTask.tmAddr);
        inPlayer->myTMTask.player = NULL;
    }
#endif
    
    MDSequenceDisposeMutex(inPlayer->sequence);
    
    /*  Send AllNoteOff (Bn 7B 00) and AllSoundOff (Bn 78 00)  */
    /*	{
     static unsigned char sAllNoteAndSoundOff[] = {0xB0, 0x7B, 0x00, 0xB0, 0x78, 0x00};
     MDTimeType lastTime = MDCalibratorTickToTime(inPlayer->calib, inPlayer->lastTick);
     SendMIDIEventsToAllTracks(inPlayer, lastTime, 6, sAllNoteAndSoundOff);
     } */
    StopSoundInAllTracks(inPlayer);
    
    inPlayer->status = kMDPlayer_ready;
    
    inPlayer->recordingStopTick = kMDMaxTick;
    
    return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerStartRecording
   -------------------------------------- */
MDStatus
MDPlayerStartRecording(MDPlayer *inPlayer)
{
    MDStatus sts = kMDNoError;
    if (inPlayer != NULL) {
        /*  Start recording  */
		if (sRecordingPlayer != NULL)
			return kMDErrorAlreadyRecording;
        MDPlayerReleaseRecordingBuffer(inPlayer);
        if (MDPlayerAllocateRecordingBuffer(inPlayer) == NULL)
            return kMDErrorOutOfMemory;
        sRecordingPlayer = inPlayer;
        inPlayer->isRecording = 1;
        sts = MDPlayerStart(inPlayer);
        if (inPlayer->status != kMDPlayer_playing && inPlayer->status != kMDPlayer_exhausted) {
            sRecordingPlayer = NULL;
            inPlayer->isRecording = 0;
        }
    }

	#if DEBUG
	{
		char buf[1024];
		snprintf(buf, sizeof buf, "%s/Alchemusica_MIDIin_dump", getenv("HOME"));
		sMIDIInputDump = fopen(buf, "w");
	}
	#endif
	
    return sts;
}

/* --------------------------------------
	･ MDPlayerStopRecording
   -------------------------------------- */
MDStatus
MDPlayerStopRecording(MDPlayer *inPlayer)
{
	if (inPlayer != NULL && inPlayer->isRecording) {
		if (sRecordingPlayer == inPlayer)
			sRecordingPlayer = NULL;
		inPlayer->isRecording = 0;
	}
	#if DEBUG
	{
		if (sMIDIInputDump != NULL)
			fclose(sMIDIInputDump);
		sMIDIInputDump = NULL;
	}
	#endif
	return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerSuspend
 -------------------------------------- */
MDStatus
MDPlayerSuspend(MDPlayer *inPlayer)
{
    MDStatus sts;
    if (inPlayer != NULL) {
        sts = MDPlayerStop(inPlayer);
        inPlayer->status = kMDPlayer_suspended;
        return sts;
    } else return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerSetRecordingStopTick
   -------------------------------------- */
MDStatus
MDPlayerSetRecordingStopTick(MDPlayer *inPlayer, MDTickType inTick)
{
	/*  Note: recording stop tick will be reset every time MDPlayerStop() is called  */
	if (inPlayer != NULL)
		inPlayer->recordingStopTick = inTick;
	return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerGetStatus
   -------------------------------------- */
MDPlayerStatus
MDPlayerGetStatus(MDPlayer *inPlayer)
{
	if (inPlayer != NULL)
		return inPlayer->status;
	else return -1;
}

/* --------------------------------------
	･ MDPlayerIsRecording
   -------------------------------------- */
int
MDPlayerIsRecording(MDPlayer *inPlayer)
{
    return inPlayer->isRecording;
}

/* --------------------------------------
	･ MDPlayerRecordingPlayer
   -------------------------------------- */
MDPlayer *
MDPlayerRecordingPlayer(void)
{
	return sRecordingPlayer;
}

/* --------------------------------------
	･ MDPlayerGetTime
   -------------------------------------- */
MDTimeType
MDPlayerGetTime(MDPlayer *inPlayer)
{
	if (inPlayer != NULL) {
		if (inPlayer->status == kMDPlayer_playing || inPlayer->status == kMDPlayer_exhausted) {
            MDTimeType now_time = GetHostTimeInMDTimeType() - inPlayer->startTime;
            if (now_time < inPlayer->countOffEndTime)
                return inPlayer->countOffEndTime;
            else return now_time;
		} else {
			return inPlayer->time;
		}
	}
	return 0;
}

/* --------------------------------------
	･ MDPlayerGetTick
   -------------------------------------- */
MDTickType
MDPlayerGetTick(MDPlayer *inPlayer)
{
	if (inPlayer != NULL) {
		if (inPlayer->status == kMDPlayer_playing || inPlayer->isRecording) {
			return MDCalibratorTimeToTick(inPlayer->calib, GetHostTimeInMDTimeType() - inPlayer->startTime);
		} else {
			return MDCalibratorTimeToTick(inPlayer->calib, inPlayer->time);
		}
	}
	return 0;
}

/* --------------------------------------
	･ MDPlayerSetMIDIThruDeviceAndChannel
   -------------------------------------- */
void
MDPlayerSetMIDIThruDeviceAndChannel(int32_t dev, int ch)
{
    sMIDIThruDevice = dev;
    sMIDIThruChannel = ch;
}

/* --------------------------------------
	･ MDPlayerSetMIDIThruTranspose
 -------------------------------------- */
void
MDPlayerSetMIDIThruTranspose(int transpose)
{
    sMIDIThruTranspose = transpose;
}

/* --------------------------------------
	･ MDPlayerSetCountOffSettings
 -------------------------------------- */
void
MDPlayerSetCountOffSettings(MDPlayer *inPlayer, MDTimeType duration, MDTimeType bar, MDTimeType beat)
{
    if (inPlayer != NULL) {
        inPlayer->countOffDuration = duration;
        inPlayer->countOffBar = bar;
        inPlayer->countOffBeat = beat;
    }
}

/* --------------------------------------
	･ MDPlayerBacktrackEvents
   -------------------------------------- */
MDStatus
MDPlayerBacktrackEvents(MDPlayer *inPlayer, MDTickType inTick, const int32_t *inEventType, const int32_t *inEventTypeLastOnly)
{
	/*  The int32_t values in inEventType[] and inEventTypeLastOnly[] are in the following format:
		lower 16 bits = MDEventKind, upper 16 bits = the 'code' field in MDEvent record.
		The value -1 is used for termination.  */
	
    MDEvent *ep;
    MDEvent **lastOnlyEvents;
	MDDestinationInfo *info;
    int i, channel, num, lastOnlyCount, processedDest;
    static const int32_t sDefaultEventType = { -1 };

	if (inEventType == NULL)
		inEventType = &sDefaultEventType;
	if (inEventTypeLastOnly == NULL)
		inEventTypeLastOnly = &sDefaultEventType;

    /*  Count the 'last only' types  */
    for (i = 0; inEventTypeLastOnly[i] != -1; i++);
    lastOnlyCount = i;
    if (lastOnlyCount > 0)
        lastOnlyEvents = (MDEvent **)calloc(sizeof(MDEvent *), lastOnlyCount * inPlayer->destNum * 16);
    else lastOnlyEvents = NULL;
    
    /*  Rewind to the top of the sequence  */
    MDPlayerJumpToTick(inPlayer, 0);
    
    /*  Use note-off track for keeping 'last only' events  */
    for (num = 0; num < inPlayer->destNum; num++) {
        info = inPlayer->destInfo[num];
        MDPointerSetPosition(info->noteOffPtr, 0);
        MDTrackClear(info->noteOff);
    }
        
    do {
        processedDest = 0;
        for (num = 0; num < inPlayer->destNum; num++) {
            int kind, code;
            int32_t n;
            info = inPlayer->destInfo[num];
            if (info->currentTick < inTick) {
                processedDest++;
                ep = info->currentEp;
                /*  Is this event to be sent?  */
                for (i = 0; (n = inEventType[i]) != -1; i++) {
                    kind = (n & 0xffff);
                    code = ((n >> 16) & 0xffff);
                    if (MDGetKind(ep) == kind && (!MDHasCode(ep) || code == 0xffff || MDGetCode(ep) == code))
                        break;
                }
                if (n != -1) {
                    /*  Schedule this event  */
                    channel = (MDTrackGetTrackChannel(info->currentTrack) & 15);
                    if (ScheduleMDEventToDevice(info->dev, 0, ep, channel) < 0)
                        continue;
                } else {
                    /*  Is this 'last only' event?  */
                    for (i = 0; i < lastOnlyCount; i++) {
                        n = inEventTypeLastOnly[i];
                        kind = (n & 0xffff);
                        code = ((n >> 16) & 0xffff);
                        if (MDGetKind(ep) == kind && (!MDHasCode(ep) || code == 0xffff || MDGetCode(ep) == code))
                            break;
                    }
                    if (i < lastOnlyCount) {
                        /*  Store this event; if the same type of event is already
                            present, then overwrite it  */
                        MDEvent ev, *ep1;
                        MDEventClear(&ev);
                        MDEventCopy(&ev, ep, 1);
                        channel = (MDTrackGetTrackChannel(info->currentTrack) & 15);
                        MDSetChannel(&ev, channel);
                        MDSetTick(&ev, 0);
                        MDPointerSetPosition(info->noteOffPtr, -1);
                        kind = MDGetKind(ep);
                        code = (MDHasCode(ep) ? MDGetCode(ep) : 0);
                        while ((ep1 = MDPointerForward(info->noteOffPtr)) != NULL) {
                            if (MDGetChannel(ep1) == channel
                                && MDGetKind(ep1) == kind
                                && (!MDHasCode(ep1) || MDGetCode(ep1) == code))
                                break;
                        }
                        if (ep1 != NULL) {
                            /*  Replace ep1 with ev  */
                            MDPointerReplaceAnEvent(info->noteOffPtr, &ev, NULL);
                        } else {
                            /*  Add ev  */
                            MDPointerInsertAnEvent(info->noteOffPtr, &ev);
                        }
                    }
                }
                info->currentEp = MDTrackMergerForward(info->merger, &(info->currentTrack));
                info->currentTick = (info->currentEp != NULL ? MDGetTick(info->currentEp) : kMDMaxTick);
            }
        }
    } while (processedDest > 0);
    /*  Send the 'last only' events  */
    for (num = 0; num < inPlayer->destNum; num++) {
        MDEvent *ep2;
        info = inPlayer->destInfo[num];
        MDPointerSetPosition(info->noteOffPtr, -1);
        while ((ep2 = MDPointerForward(info->noteOffPtr)) != NULL) {
            ScheduleMDEventToDevice(info->dev, 0, ep2, 0);
        }
        MDPointerSetPosition(info->noteOffPtr, 0);
        MDTrackClear(info->noteOff);
        info->noteOffTick = kMDMaxTick;
    }
    inPlayer->lastTick = inTick;
    inPlayer->time = MDCalibratorTickToTime(inPlayer->calib, inTick);
    return 0;
#if 0
	/*  eventWithDestList[]: record the event to be sent  */
	maxIndex = 256;
	eventWithDestList = (EventWithDest *)malloc(maxIndex * sizeof(EventWithDest));
	if (eventWithDestList == NULL) {
		MDMergerRelease(merger);
		return kMDErrorOutOfMemory;
	}
	index = 0;

	while ((ep = MDMergerBackward(merger)) != NULL) {
		unsigned short kind, code;
		track = MDMergerGetCurrentTrack(merger);
		dest = inPlayer->destIndex[track];
		if (dest < 0 || inPlayer->destInfo[dest] == NULL)
			continue;	/*  No output  */
		for (num = 0; (n = inEventType[num]) != -1; num++) {
			kind = (n & 0xffff);
			code = ((n >> 16) & 0xffff);
			if (MDGetKind(ep) == kind && (!MDHasCode(ep) || code == 0xffff || MDGetCode(ep) == code))
				break;
		}
		if (n == -1) {
			for (num = 0; (n = inEventTypeLastOnly[num]) != -1; num++) {
				kind = (n & 0xffff);
				code = ((n >> 16) & 0xffff);
				if (MDGetKind(ep) == kind && (!MDHasCode(ep) || code == 0xffff || MDGetCode(ep) == code)) {
					/*  Search eventWithDestList[] if this type of event is already registered  */
					for (n = 0; n < index; n++) {
						MDEvent *ep2;
						if (eventWithDestList[n].dest != dest)
							continue;
						ep2 = eventWithDestList[n].ep;
						if (MDGetChannel(ep2) != MDGetChannel(ep) || MDGetKind(ep2) != MDGetKind(ep))
							continue;
						if (MDHasCode(ep) && MDGetCode(ep2) != MDGetCode(ep))
							continue;
						break;	/*  Found (which means this event must be skipped)  */
					}
					if (n < index)
						ep = NULL;
					break;
				}
			}
			if (n == -1)
				ep = NULL;
		}
		/*  If ep != NULL, then this event should be sent  */
		if (ep != NULL) {
			if (index >= maxIndex) {
				/*  eventWithDestList[] should be expanded  */
				void *p;
				maxIndex += 256;
				p = realloc(eventWithDestList, maxIndex * sizeof(EventWithDest));
				if (p == NULL) {
					free(eventWithDestList);
					MDMergerRelease(merger);
					return kMDErrorOutOfMemory;
				}
				eventWithDestList = (EventWithDest *)p;
			}
			eventWithDestList[index].ep = ep;
			eventWithDestList[index].dest = dest;
			index++;
		}
	}

	/*  Send the events  */
	for (num = index - 1; num >= 0; num--) {
		ep = eventWithDestList[num].ep;
		dest = eventWithDestList[num].dest;
		info = inPlayer->destInfo[dest];
		if (MDIsSysexEvent(ep)) {
			/*  Prepare a MIDISysexSendRequest  */
			MIDISysexSendRequest *rp = &info->sysexRequest;
			rp->destination = info->eref;
			rp->data = (Byte *)MDGetMessageConstPtr(ep, &n);
			rp->bytesToSend = n;
			rp->complete = 0;
			rp->completionProc = MySysexCompletionProc;
			rp->completionRefCon = info;
			MIDISendSysex(&info->sysexRequest);
			my_usleep(40000);
			while (rp->complete == 0)
				my_usleep(1000);
		} else {
			unsigned char buf[4];
			memset(buf, 0, 4);
			n = MDEventToMIDIMessage(ep, buf);
            buf[0] |= inPlayer->destChannel[track];
			info->packetPtr = MIDIPacketListInit(&info->packetList);
			info->packetPtr = MIDIPacketListAdd(&info->packetList, sizeof(info->packetList), info->packetPtr,
				0, n, buf);
			MIDISend(sMIDIOutputPortRef, info->eref, &info->packetList);
			my_usleep(n * 400);
		}
	}
	free(eventWithDestList);
	MDMergerRelease(merger);
	return kMDNoError;
#endif
}

static int
sMDPlayerGetOneByte(void *ptr)
{
    MDPlayer *player = (MDPlayer *)ptr;
    if (player->tempStorageIndex >= player->tempStorageLength)
        return -1;
    else return player->tempStorage[player->tempStorageIndex++];
}

/* --------------------------------------
	･ MDPlayerGetRecordedEvents
   -------------------------------------- */
/*  *outEvent must be either NULL or a memory block allocated by malloc, and *outEventBufSiz
    must be the number of MDEvents that (*outEvent)[] can store. Both *outEvent and
    *outEventBufSiz can be changed by realloc.
	Returns the number of events.  */
int
MDPlayerGetRecordedEvents(MDPlayer *inPlayer, MDEvent **outEvent, int *outEventBufSiz)
{
    int result;
    MDTimeType timeStamp;
    MDTickType tick;
	int eventCount = 0, n;
	while (eventCount == 0) {
		result = MDPlayerGetRecordingData(inPlayer, &timeStamp, &(inPlayer->tempStorageLength), &(inPlayer->tempStorage), &(inPlayer->tempStorageSize));
		dprintf(2, "get record data result %d, timeStamp %g, length %ld, data %p\n", result, (double)timeStamp, inPlayer->tempStorageLength, inPlayer->tempStorage);
		if (result == -1)
			return 0;
		else if (result < 0)
			return result;
		if (outEvent == NULL)
			break;  /*  Just skip this block  */
		inPlayer->tempStorageIndex = 0;
		while ((n = sMDPlayerGetOneByte(inPlayer)) >= 0) {
			MDEvent tempEvent;
			MDEventInit(&tempEvent);
			if (n == 0xf0) {
				/*  System Exclusive  */
				int32_t len = 1;  /*  Include the first 0xf0 byte  */
				while ((n = sMDPlayerGetOneByte(inPlayer)) >= 0 && n != 0xf7)
					len++;
				if (n == 0xf7)
					len++;
				else inPlayer->tempStorageIndex--;  /*  unget the last byte  */
				MDSetKind(&tempEvent, kMDEventSysex);
				if (MDSetMessageLength(&tempEvent, len) < len) {
					MDEventInit(&tempEvent);
					return kMDErrorOutOfMemory;
				}
				/*  Do we need to add extra 0xf7 if it is absent...?  */
				MDSetMessage(&tempEvent, inPlayer->tempStorage + inPlayer->tempStorageIndex - len);
			} else if (n >= 0 && n < 0xf0) {
				/*  MIDI Event  */
				MDStatus sts;
				sts = MDEventFromMIDIMessage(&tempEvent, n, inPlayer->runningStatusByte, sMDPlayerGetOneByte, inPlayer, &(inPlayer->runningStatusByte));
				if (sts != kMDNoError) {
					MDEventInit(&tempEvent);
					return sts;
				}
			} else {
				/*  realtime events: skipped  */
				continue;
			/*	MDEventInit(outEvent);
				return kMDErrorNoEvents; */
			}
            tick = MDCalibratorTimeToTick(inPlayer->calib, timeStamp);
            if (tick < inPlayer->recordingStopTick) {
                MDSetTick(&tempEvent, tick);
                if (*outEvent == NULL || eventCount >= *outEventBufSiz) {
                    /*  (Re)allocate the event buffer  */
                    int allocSize = *outEventBufSiz + 8;
                    MDEvent *ep = (MDEvent *)calloc(sizeof(MDEvent), allocSize);
                    if (*outEvent != NULL && *outEventBufSiz > 0)
                        MDEventMove(ep, *outEvent, *outEventBufSiz);
                    *outEventBufSiz = allocSize;
                    if (*outEvent != NULL)
                        free(*outEvent);
                    *outEvent = ep;
                }
                MDEventMove(*outEvent + eventCount, &tempEvent, 1);
                eventCount++;
            } else {
                /*  If the tick exceeds recordingStopTick, then do not collect it  */
                /*  This does not happen so often, because recording should be stopped
                 by PlayingViewController after a while  */
                MDEventClear(&tempEvent);
            }
		}
	}
    return eventCount;
}

/* --------------------------------------
	･ MDPlayerClearRecordedEvents
   -------------------------------------- */
void
MDPlayerClearRecordedEvents(MDPlayer *inPlayer)
{
    MDPlayerReleaseRecordingBuffer(inPlayer);
    MDPlayerAllocateRecordingBuffer(inPlayer);
}

