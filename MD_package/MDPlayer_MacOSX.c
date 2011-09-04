/*
 *  MDPlayer_MacOSX.c
 *
 *  Created by Toshi Nagata on Sun Jul 01 2001.

   Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

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

typedef struct MDDeviceIDRecord {
	char *      name;
	
	/*  OS-specific fields for identification of devices  */
	int         uniqueID;       /*  CoreMIDI device  */

} MDDeviceIDRecord;

typedef struct MDDeviceInfo {
	char		initialized;	/*  non-zero if already initialized  */
	long		destNum;		/*  The number of destinations  */
	MDDeviceIDRecord *dest;		/*  The names of destinations  */
	long		sourceNum;		/*  The number of sources  */
	MDDeviceIDRecord *source;	/*  The names of sources  */
} MDDeviceInfo;

/*  Information for MIDI output  */
typedef struct MDDestinationInfo {
	long	refCount;
	long	dev;

	/*  CoreMIDI (Mac OS X) specfic fields  */
	long	bytesToSend;
	MIDIEndpointRef	eref;
	MIDIPacketList	packetList;
	MIDIPacket *	packetPtr;
	MDTimeType		timeOfLastEvent;
	MIDISysexSendRequest	sysexRequest;
	char			sysexTransmitting;		/* non-zero if sysexRequest is being processed */

} MDDestinationInfo;

/*
static MDDestinationInfo *MDPlayerNewDestinationInfo(long dev);
static void	MDPlayerInitDestinationInfo(long dev, MDDestinationInfo *outInfo);
static void MDPlayerReleaseDestinationInfo(MDDestinationInfo *info);
*/

static MDDeviceInfo sDeviceInfo = { 0, 0, NULL, 0, NULL };

/*  CoreMIDI (Mac OS X) specific static variables  */
static MIDIClientRef	sMIDIClientRef = NULL;
static MIDIPortRef		sMIDIInputPortRef = NULL;
static MIDIPortRef		sMIDIOutputPortRef = NULL;

/*  Forward declaration of the MIDI read callback  */
static void MyMIDIReadProc(const MIDIPacketList *pktlist, void *refCon, void *connRefCon);

#define kMDRecordingBufferSize	32768
/*#define kMDRecordingBufferSize	99  *//*  Small buffer for debugging  */

typedef struct MDRecordingBuffer {
    struct MDRecordingBuffer *next;
    long size;
    unsigned char data[4];
} MDRecordingBuffer;

typedef struct MDRecordingEventHeader {
    MDTimeType	timeStamp;
    long size;
} MDRecordingEventHeader;

struct MDPlayer {
	long			refCount;
	MDMerger *		merger;
	MDCalibrator *	calib;		/*  for tick <-> time conversion  */
	MDTimeType		time;		/*  the last time when interrupt fired  */
	MDTimeType		startTime;	/*  In microseconds  */
	MDTickType      stopTick;
	MDTickType		lastTick;	/*  tick of the last event already sent  */
	MDPlayerStatus	status;
	int				trackNum;   /*  Number of tracks when this MDPlayer is initialized  */
								/*  (= size of destIndex[], destChannel[], trackAttr[] ) */
	long			*destIndex;		/*  The index to destInfo[] for each track  */
	long			destNum;		/*  The number of destinations used in this player  */
	MDDestinationInfo	**destInfo;	/*  Information for MIDI output  */
    unsigned char	*destChannel;	/*  Output channel for each track (single-channel mode) */
    MDTrackAttribute	*trackAttr;		/*  Track attributes for each track  */

	MDTrack *		noteOff;		/*  Keep the note-off events for output  */
	MDPointer *		noteOffPtr;
	MDTickType		noteOffTick;

	MDTickType		nextMetronomeBar;  /*  Tick to ring the metronome bell (top of bar)  */
	MDTickType		nextMetronomeBeat; /*  Tick to ring the metronome click (each beat)  */
	int             metronomeBar;      /*  Bar length  */
	int             metronomeBeat;     /*  Beat length  */
	MDTickType      nextTimeSignature; /*  Next time signature change for metronome  */

    unsigned char	isRecording;
/*    unsigned char	isRefreshingInternalInfo;	*//*  Suspend MIDI output while updating destination information  */
	unsigned char   shouldTerminate; /*  Flag to request the playing thread to terminate */

	MDAudio *		audio;

    /*  Recording buffer  */
/*    MDRecordingBuffer *firstBuffer;  */
    MDRecordingBuffer *topBuffer;
    long topPos;
    long topSize;
    MDRecordingBuffer *bottomBuffer;
    long bottomPos;
    long bottomSize;
    MDRecordingBuffer *topFreeBuffer;
    MDRecordingBuffer *bottomFreeBuffer;

    /*  Temporary storage for converting recorded data to MDEvent  */
    unsigned char *	tempStorage;
    long			tempStorageSize;
    long			tempStorageLength;
    long			tempStorageIndex;
    unsigned char	runningStatusByte;

	/*  CoreMIDI (Mac OS X) specific fields  */
#if !USE_TIME_MANAGER
	pthread_t  playThread;
	
#else
	MyTMTask		myTMTask;
#endif
};

static MDPlayer *sRecordingPlayer = NULL;	/*  the MDPlayer that receives the incoming MIDI messages */
static long sMIDIThruDevice = -1;
static MIDIEndpointRef sMIDIThruDeviceRef = NULL;
static int sMIDIThruChannel = 0;  /*  0..15; if 16, then incoming channel number is kept */

/*  Minimum interval of interrupts  */
#define	kMDPlayerMinimumInterval	50000   /* 50 msec */
#define kMDPlayerMaximumInterval    100000  /* 100 msec */

/*  Prefetch interval  */
#define kMDPlayerPrefetchInterval	100000  /* 100 msec */

MetronomeInfoRecord gMetronomeInfo;

#pragma mark ====== Utility function  ======

int
my_usleep(unsigned long useconds)
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
MDPlayerReloadDeviceInformationSub(MDDeviceIDRecord **src_dst_p, long *src_dst_Num_p, int is_dst)
{
	MIDIEndpointRef eref, eref1;
	MIDIDeviceRef dref;
	MIDIEntityRef entref;
	CFStringRef name, devname, name1;
	long n, dev, ent, en, num;
	char buf[256], *p;
	SInt32 uniqueID;
	int i;

	/*  Look up all src/dst, compare the unique ID, and update the name  */
	num = (is_dst ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources());
	for (n = 0; n < num; n++) {
		eref = (is_dst ? MIDIGetDestination(n) : MIDIGetSource(n));
		MIDIObjectGetStringProperty(eref, kMIDIPropertyName, &name);
		if (MIDIObjectGetIntegerProperty(eref, kMIDIPropertyUniqueID, &uniqueID) != noErr)
			uniqueID = 0;
		/*  Search the device/entity/endpoint tree  */
		for (dev = MIDIGetNumberOfDevices() - 1; dev >= 0; dev--) {
			dref = MIDIGetDevice(dev);
			for (ent = MIDIDeviceGetNumberOfEntities(dref) - 1; ent >= 0; ent--) {
				entref = MIDIDeviceGetEntity(dref, ent);
				en = (is_dst ? MIDIEntityGetNumberOfDestinations(entref) : MIDIEntityGetNumberOfSources(entref)) - 1;
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
		if (!CFStringGetCString(name, buf, 255, CFStringGetSystemEncoding()))
			sprintf(buf, "(Device %ld)", n);
		buf[255] = 0;
		/*  Look up in the existing table whether this device is already there (by uniqueID) */
		for (i = 0; i < *src_dst_Num_p; i++) {
			if ((*src_dst_p)[i].uniqueID == uniqueID)
				break;
		}
	/*	if (i >= *src_dst_Num_p) {
			MDDeviceIDRecord *idp;
			if ((*src_dst_p) != NULL)
				idp = (MDDeviceIDRecord *)realloc((*src_dst_p), sizeof(MDDeviceIDRecord) * (i + 1));
			else
				idp = (MDDeviceIDRecord *)malloc(sizeof(MDDeviceIDRecord) * (i + 1));
			memset(&idp[i], 0, sizeof(MDDeviceIDRecord));
			(*src_dst_p) = idp;
			(*src_dst_Num_p) = (i + 1);
			(*src_dst_p)[i].uniqueID = uniqueID;
		} */
		if (i >= 0 && i < *src_dst_Num_p) {
			/*  If found, then update the name  */
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
			/*  And update the uniqueID  */
			if (i >= 0 && i < *src_dst_Num_p)
				(*src_dst_p)[i].uniqueID = uniqueID;
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
	int n;
	if (sDeviceInfo.initialized)
		return;

	if (sMIDIClientRef == NULL)
		MIDIClientCreate(CFSTR("Alchemusica"), sCoreMIDINotifyProc, NULL, &sMIDIClientRef);
	if (sMIDIOutputPortRef == NULL)
		MIDIOutputPortCreate(sMIDIClientRef, CFSTR("Output port"), &sMIDIOutputPortRef);
	if (sMIDIInputPortRef == NULL)
		MIDIInputPortCreate(sMIDIClientRef, CFSTR("Input port"), MyMIDIReadProc, NULL, &sMIDIInputPortRef);
	/*  Start receiving incoming MIDI messages  */
	for (n = MIDIGetNumberOfSources() - 1; n >= 0; n--) {
		MIDIPortConnectSource(sMIDIInputPortRef, MIDIGetSource(n), (void *)n);
	/*	dprintf(0, "connecting input source %d\n", (int)n); */
	}
	sDeviceInfo.initialized = 1;
}

/* --------------------------------------
	･ MDPlayerReloadDeviceInformation
   -------------------------------------- */
void
MDPlayerReloadDeviceInformation(void)
{
	if (!sDeviceInfo.initialized)
		MDPlayerInitCoreMIDI();
	/*  Update the device information  */
	/*  The device index to the same device [i.e. the device with the same uniqueID] remains the same.  */
	MDPlayerReloadDeviceInformationSub(&(sDeviceInfo.dest), &(sDeviceInfo.destNum), 1);
	MDPlayerReloadDeviceInformationSub(&(sDeviceInfo.source), &(sDeviceInfo.sourceNum), 0);
}

/* --------------------------------------
	･ MDPlayerGetNumberOfDestinations
   -------------------------------------- */
long
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
MDPlayerGetDestinationName(long dev, char *name, long sizeof_name)
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
long
MDPlayerGetDestinationNumberFromName(const char *name)
{
    long dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.destNum; dev++) {
        if (strcmp(name, sDeviceInfo.dest[dev].name) == 0)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerGetDestinationUniqueID
   -------------------------------------- */
long
MDPlayerGetDestinationUniqueID(long dev)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	if (dev >= 0 && dev < sDeviceInfo.destNum) {
		return sDeviceInfo.dest[dev].uniqueID;
	} else return -1;
}

/* --------------------------------------
	･ MDPlayerGetDestinationNumberFromUniqueID
   -------------------------------------- */
long
MDPlayerGetDestinationNumberFromUniqueID(long uniqueID)
{
    long dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.destNum; dev++) {
        if (uniqueID == sDeviceInfo.dest[dev].uniqueID)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerGetNumberOfSources
   -------------------------------------- */
long
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
MDPlayerGetSourceName(long dev, char *name, long sizeof_name)
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
long
MDPlayerGetSourceNumberFromName(const char *name)
{
    long dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.sourceNum; dev++) {
        if (strcmp(name, sDeviceInfo.source[dev].name) == 0)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerGetSourceUniqueID
   -------------------------------------- */
long
MDPlayerGetSourceUniqueID(long dev)
{
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	if (dev >= 0 && dev < sDeviceInfo.sourceNum) {
		return sDeviceInfo.source[dev].uniqueID;
	} else return -1;
}

/* --------------------------------------
	･ MDPlayerGetSourceNumberFromUniqueID
   -------------------------------------- */
long
MDPlayerGetSourceNumberFromUniqueID(long uniqueID)
{
    long dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
    for (dev = 0; dev < sDeviceInfo.sourceNum; dev++) {
        if (uniqueID == sDeviceInfo.source[dev].uniqueID)
            return dev;
    }
    return -1;
}

/* --------------------------------------
	･ MDPlayerAddDestinationName
   -------------------------------------- */
long
MDPlayerAddDestinationName(const char *name)
{
	long dev;
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
long
MDPlayerAddSourceName(const char *name)
{
	long dev;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
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
	･ MDPlayerInitDestinationInfo
   -------------------------------------- */
static void
MDPlayerInitDestinationInfo(long dev, MDDestinationInfo *info)
{
	/*  CoreMIDI (Mac OS X) specfic initialization  */
	info->bytesToSend = 0;
	info->sysexTransmitting = 0;
	info->packetPtr = MIDIPacketListInit(&info->packetList);
	info->eref = NULL;
	if (dev >= 0 && dev < sDeviceInfo.destNum) {
		MIDIObjectType objType;
		MIDIObjectRef eref;
	/*	info->eref = MIDIGetDestination(dev); */
		if (MIDIObjectFindByUniqueID(sDeviceInfo.dest[dev].uniqueID, &eref, &objType) == noErr && objType == kMIDIObjectType_Destination)
			info->eref = eref;
	}
}

/* --------------------------------------
	･ MDPlayerNewDestinationInfo
   -------------------------------------- */
static MDDestinationInfo *
MDPlayerNewDestinationInfo(long dev)
{
	MDDestinationInfo *info;
/*	if (!sDeviceInfo.initialized)
		MDPlayerReloadDeviceInformation(); */
	info = (MDDestinationInfo *)malloc(sizeof(MDDestinationInfo));
	if (info == NULL)
		return NULL;
	memset(info, 0, sizeof(MDDestinationInfo));
	info->refCount = 1;
    info->dev = dev;
	MDPlayerInitDestinationInfo(dev, info);
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
			
			/*  CoreMIDI (Mac OS X) specfic release protocol  */
			
			free(info);
		}
	}
}

#pragma mark ====== Internal MIDI Functions ======

#if DEBUG
static FILE *sMIDIInputDump;
#endif

//#define GetHostTimeInMDTimeType()	((MDTimeType)((AudioConvertHostTimeToNanos(AudioGetCurrentHostTime()) / 1000)))
#define ConvertMDTimeTypeToHostTime(tm)	AudioConvertNanosToHostTime((UInt64)(tm) * 1000)
#define ConvertHostTimeToMDTimeType(tm) ((MDTimeType)(AudioConvertHostTimeToNanos(tm) / 1000))
#define GetHostTimeInMDTimeType() ConvertHostTimeToMDTimeType(AudioGetCurrentHostTime())

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
MDPlayerPutRecordingData(MDPlayer *inPlayer, MDTimeType timeStamp, long size, const unsigned char *buf)
{
    unsigned char *op;
    MDRecordingEventHeader header;
    MDRecordingBuffer *topBuffer;
    long topPos;
    long nsize, n;

	#if DEBUG
	if (0) {
		if (sMIDIInputDump != NULL) {
			int i;
			fprintf(sMIDIInputDump, "%qd ", (long long)timeStamp);
			for (i = 0; i < size; i++) {
				fprintf(sMIDIInputDump, "%02x%c", buf[i], (i == size - 1 ? '\n' : ' '));
			}
		}
	}
	#endif
	
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
MDPlayerGetRecordingData(MDPlayer *inPlayer, MDTimeType *outTimeStamp, long *outSize, unsigned char **outBuf, long *outBufSize)
{
    /*  **outBuf and *outBufSize must contain valid values on calling, with a malloc'ed
        pointer in **outBuf and its size in *outBufSize. On return, both may be changed
        via realloc() when the buffer size is not sufficient  */
    unsigned char *ip, *op;
    MDRecordingEventHeader header;
    MDRecordingBuffer *bottomBuffer;
    long bottomPos;
    long size, n;
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
			fprintf(sMIDIInputDump, "-%qd ", (long long)*outTimeStamp);
			for (i = 0; i < header.size; i++) {
				fprintf(sMIDIInputDump, "%02x%c", (*outBuf)[i], (i == header.size - 1 ? '\n' : ' '));
			}
		}
	}
#endif
    return 0;
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
        if (recordingFlag) {
            if (packet->timeStamp != 0) {
                myTimeStamp = ConvertHostTimeToMDTimeType(packet->timeStamp) - sRecordingPlayer->startTime;
            } else myTimeStamp = now;
            n = MDPlayerPutRecordingData(sRecordingPlayer, myTimeStamp, (long)(packet->length), (unsigned char *)(packet->data));
        }
        /*  Rechannelize status bytes  */
		if (sMIDIThruChannel >= 0 && sMIDIThruChannel < 16) {
		/*	dprintf(0, "MyMIDIReadProc; rechannelize status bytes\n"); */
			for (j = 0; j < packet->length; j++) {
				if (packet->data[j] >= 0x80 && packet->data[j] < 0xf0)
					packet->data[j] = (packet->data[j] & 0xf0) | sMIDIThruChannel;
			}
		}
    }

    /*  Echo back  */
    if (sMIDIThruDeviceRef != NULL)
        MIDISend(sMIDIOutputPortRef, sMIDIThruDeviceRef, pktlist);
}

static void
MySysexCompletionProc(MIDISysexSendRequest *request)
{
	request->bytesToSend = 0;
	((MDDestinationInfo *)(request->completionRefCon))->sysexTransmitting = 0;
}

static void
RegisterEventInNoteOffTrack(MDPlayer *inPlayer, const MDEvent *ep)
{
	MDEvent *ep0;
	MDPointerJumpToTick(inPlayer->noteOffPtr, MDGetTick(ep) + 1);
	MDPointerInsertAnEvent(inPlayer->noteOffPtr, ep);
	MDPointerSetPosition(inPlayer->noteOffPtr, 0);
	if ((ep0 = MDPointerCurrent(inPlayer->noteOffPtr)) != NULL)
		inPlayer->noteOffTick = MDGetTick(ep0);
	else inPlayer->noteOffTick = kMDMaxTick;
}

static void
PrepareMetronomeForTick(MDPlayer *inPlayer, MDTickType inTick)
{
	MDEvent *ep;
	long timebase = MDSequenceGetTimebase(MDMergerGetSequence(inPlayer->merger));
	MDTickType t, t0;
	MDCalibratorJumpToTick(inPlayer->calib, inTick);
	ep = MDCalibratorGetEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
	if (ep == NULL) {
		t = 0;
		inPlayer->metronomeBeat = timebase;
		inPlayer->metronomeBar = timebase * 4;
	} else {
		const unsigned char *p = MDGetMetaDataPtr(ep);
		t = MDGetTick(ep);
		inPlayer->metronomeBeat = timebase * p[2] / 24;
		inPlayer->metronomeBar = timebase * p[0] * 4 / (1 << p[1]);
	}
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

static long
SendMIDIEventsBeforeTick(MDPlayer *inPlayer, MDTickType now_tick, MDTickType prefetch_tick, MDTickType *outNextTick)
{
	MDTimeType nextTime, lastTime;
	MDTickType nextTick;
	MDMerger *merger;
	MDEvent *ep;
	OSStatus sts;
	unsigned char buf[4];
	const unsigned char *p;
	int track, processed;
	long dev, n, bytesSent;
	MDDestinationInfo *info;
	unsigned char isNoteOff;

	/*  Initialize the MIDIPacketLists  */
	for (n = inPlayer->destNum - 1; n >= 0; n--) {
		info = inPlayer->destInfo[n];
		if (info != NULL)
			info->packetPtr = MIDIPacketListInit(&info->packetList);
	}
	
	merger = inPlayer->merger;
	lastTime = 0;
	MDPointerSetPosition(inPlayer->noteOffPtr, 0);
	processed = 0;
	dev = -1;

	/*  Create the MIDIPacketLists  */
	while (1) {
		if (inPlayer->noteOffTick <= MDMergerGetTick(merger)) {
			ep = MDPointerCurrent(inPlayer->noteOffPtr);
			if (ep != NULL && MDGetKind(ep) != kMDEventSpecial)
				dev = MDGetLData(ep);
			isNoteOff = 1;
		} else {
			ep = MDMergerCurrent(merger);
			track = MDMergerGetCurrentTrack(merger);
			isNoteOff = 0;
		}
		if (ep == NULL) {
			nextTick = kMDMaxTick;
			break;	/*  No more data  */
		}
		if (MDIsMetaEvent(ep))
			goto next;	/*  Skip meta events  */
		nextTick = MDGetTick(ep);
		if (nextTick > prefetch_tick)
			break;	/*  This should be after meta-event check  */

		if (MDGetKind(ep) == kMDEventSpecial) {
			int code;
			if (nextTick > now_tick)
				break;  /*  Should be processed in the next interrupt cycle  */
			code = MDGetCode(ep);
			if (code == kMDSpecialEndOfSequence || code == kMDSpecialStopPlaying) {
				if (inPlayer->isRecording)
					MDPlayerStopRecording(inPlayer);
				if (MDAudioIsRecording())
					MDAudioStopRecording();
				inPlayer->status = kMDPlayer_exhausted;
			}
			break;
		}

        if (isNoteOff == 0) {
			if (track >= inPlayer->trackNum)
				goto next;  /*  track number out of range  */
            if (inPlayer->trackAttr[track] & (kMDTrackAttributeMute | kMDTrackAttributeMuteBySolo))
                goto next;	/*  Mute --- no output  */    
            dev = inPlayer->destIndex[track];
        }
        
		if (dev < 0 || dev >= inPlayer->destNum || (info = inPlayer->destInfo[dev]) == NULL)
			goto next;	/*  No output  */
		if (info->sysexTransmitting)
			break;		/*  Sysex is being transmitted on this device: no more output  */

		if (MDIsSysexEvent(ep)) {
			p = MDGetMessageConstPtr(ep, &n);
		} else if (MDIsChannelEvent(ep)) {
			memset(buf, 0, 4);
			n = MDEventToMIDIMessage(ep, buf);
            if (isNoteOff == 0)
                buf[0] |= inPlayer->destChannel[track];
			p = buf;
			/*  For debug  */
            dprintf(2, "Port %d, (%08ld) %02X %02X %02X\n", (int)inPlayer->destIndex[track], (long)MDGetTick(ep), (int)buf[0], (int)buf[1], (int)buf[2]);
			/*  ---------  */
			if (MDGetKind(ep) == kMDEventNote) {
				/*  Register note-off */
				MDEvent event;
				MDEventInit(&event);
				MDSetKind(&event, kMDEventInternalNoteOff);
				MDSetCode(&event, MDGetCode(ep));
				MDSetChannel(&event, inPlayer->destChannel[track]);
				MDSetNoteOffVelocity(&event, MDGetNoteOffVelocity(ep));
				MDSetTick(&event, MDGetTick(ep) + MDGetDuration(ep));
				MDSetLData(&event, dev);
				RegisterEventInNoteOffTrack(inPlayer, &event);
                dprintf(2, "register note-off (total %ld), tick %ld code %d vel %d\n", MDTrackGetNumberOfEvents(inPlayer->noteOff), MDGetTick(&event), MDGetCode(&event), MDGetNoteOffVelocity(&event));
			}
		} else goto next;	/*  Not a MIDI event  */

		inPlayer->lastTick = MDGetTick(ep);

		/*  Calculate the time stamp  */
		nextTime = MDCalibratorTickToTime(inPlayer->calib, nextTick);
		if (nextTime <= lastTime)
			nextTime = lastTime + 10;
		info->packetPtr = MIDIPacketListAdd(&info->packetList, sizeof(info->packetList), info->packetPtr,
			ConvertMDTimeTypeToHostTime(nextTime + inPlayer->startTime), n, (Byte *)p);
		if (info->packetPtr == NULL) {
			if (MDIsSysexEvent(ep)) {
				/*  Prepare a MIDISysexSendRequest  */
				MIDISysexSendRequest *rp = &info->sysexRequest;
				rp->destination = info->eref;
				rp->data = (Byte *)p;
				rp->bytesToSend = n;
				rp->complete = 0;
				rp->completionProc = MySysexCompletionProc;
				rp->completionRefCon = info;
				lastTime = nextTime;
				MDMergerForward(merger);
				nextTick = MDMergerGetTick(merger);
			}
			break;
		}
		info->bytesToSend += n;
		lastTime = nextTime;
	next:
		if (isNoteOff) {
			MDPointerDeleteAnEvent(inPlayer->noteOffPtr, NULL);
			MDPointerSetPosition(inPlayer->noteOffPtr, 0);
			if ((ep = MDPointerCurrent(inPlayer->noteOffPtr)) != NULL)
				inPlayer->noteOffTick = MDGetTick(ep);
			else inPlayer->noteOffTick = kMDMaxTick;
            dprintf(2, "%s[%d]: unregister note-off (total %ld)\n", MDTrackGetNumberOfEvents(inPlayer->noteOff));
		} else {
			MDMergerForward(merger);
		}
		processed++;
	}
	
	/*  Send the MIDI packet  */
	bytesSent = 0;
	for (n = inPlayer->destNum - 1; n >= 0; n--) {
		info = inPlayer->destInfo[n];
		if (info != NULL) {
			if (info->bytesToSend > 0) {
				sts = MIDISend(sMIDIOutputPortRef, info->eref, &info->packetList);
				if (bytesSent < info->bytesToSend)
					bytesSent = info->bytesToSend;
				info->bytesToSend = 0;
			}
			if (info->sysexTransmitting == 0 && info->sysexRequest.bytesToSend > 0) {
				/*  Send the last sysex using MIDISendSysex  */
				info->sysexTransmitting = 1;
				MIDISendSysex(&info->sysexRequest);
				if (bytesSent < info->sysexRequest.bytesToSend)
					bytesSent = info->sysexRequest.bytesToSend;				
			}
		}
	}
	
	/*  Ring metronome  */
	if (gMetronomeInfo.enableWhenPlay || (gMetronomeInfo.enableWhenRecord && inPlayer->isRecording)) {
		unsigned char note1, note2, vel1, vel2;
		buf[0] = 0x90 + (gMetronomeInfo.channel & 15);
		note1 = gMetronomeInfo.note1;
		note2 = gMetronomeInfo.note2;
		vel1 = gMetronomeInfo.vel1;
		vel2 = gMetronomeInfo.vel2;
		dev = gMetronomeInfo.dev;
		if (inPlayer->nextMetronomeBeat < 0) {
			PrepareMetronomeForTick(inPlayer, now_tick);
		}
		while (inPlayer->nextMetronomeBeat < nextTick) {
			if (inPlayer->nextMetronomeBeat >= inPlayer->nextMetronomeBar) {
				/*  Ring the bell  */
				nextTick = inPlayer->nextMetronomeBar;
				buf[1] = note1;
				buf[2] = vel1;
				if (inPlayer->nextMetronomeBar == inPlayer->nextTimeSignature) {
					/*  Update the new beat/bar  */
					long timebase = MDSequenceGetTimebase(MDMergerGetSequence(inPlayer->merger));
					MDCalibratorJumpToTick(inPlayer->calib, inPlayer->nextTimeSignature);
					ep = MDCalibratorGetEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
					if (ep == NULL) {
						/*  This cannot happen ... */
						inPlayer->metronomeBeat = timebase;
						inPlayer->metronomeBar = timebase * 4;
					} else {
						const unsigned char *p = MDGetMetaDataPtr(ep);
						inPlayer->metronomeBeat = timebase * p[2] / 24;
						inPlayer->metronomeBar = timebase * p[0] * 4 / (1 << p[1]);
					}
					ep = MDCalibratorGetNextEvent(inPlayer->calib, NULL, kMDEventTimeSignature, -1);
					if (ep == NULL)
						inPlayer->nextTimeSignature = kMDMaxTick;
					else inPlayer->nextTimeSignature = MDGetTick(ep);
				}
				inPlayer->nextMetronomeBeat = inPlayer->nextMetronomeBar + inPlayer->metronomeBeat;
				inPlayer->nextMetronomeBar += inPlayer->metronomeBar;
				if (inPlayer->nextMetronomeBar > inPlayer->nextTimeSignature)
					inPlayer->nextMetronomeBar = inPlayer->nextTimeSignature;
			} else {
				/*  Ring the click  */
				nextTick = inPlayer->nextMetronomeBeat;
				buf[1] = note2;
				buf[2] = vel2;
				inPlayer->nextMetronomeBeat += inPlayer->metronomeBeat;
			}
			if (inPlayer->nextMetronomeBeat > inPlayer->nextMetronomeBar)
				inPlayer->nextMetronomeBeat = inPlayer->nextMetronomeBar;
			nextTime = MDCalibratorTickToTime(inPlayer->calib, nextTick);
			MDPlayerSendRawMIDI(inPlayer, buf, 3, dev, nextTime);
			buf[2] = 0;
			MDPlayerSendRawMIDI(inPlayer, buf, 3, dev, nextTime + 80000);
		}
	} else inPlayer->nextMetronomeBeat = -1;  /*  Disable internal information  */
	
	*outNextTick = nextTick;
	return bytesSent;
}

static long
MyTimerFunc(MDPlayer *player)
{
	MDTimeType now_time, next_time, last_time;
	MDTickType now_tick, prefetch_tick, tick;
	MDMerger *merger;
	MDSequence *sequence;
	long n;
	
	if (player == NULL || (merger = player->merger) == NULL)
		return -1;

	sequence = MDMergerGetSequence(player->merger);
	
	now_time = GetHostTimeInMDTimeType() - player->startTime;
	now_tick = MDCalibratorTimeToTick(player->calib, now_time);
	prefetch_tick = MDCalibratorTimeToTick(player->calib, now_time + kMDPlayerPrefetchInterval);
	last_time = 0;
	
    if (MDSequenceTryLock(sequence) == 0) {
        n = SendMIDIEventsBeforeTick(player, now_tick, prefetch_tick, &tick);
		MDSequenceUnlock(sequence);
    } else {
        n = 0;
        tick = prefetch_tick + 1;
    }
    
	player->time = now_time;
	if (tick >= kMDMaxTick || player->status == kMDPlayer_exhausted) {
		player->status = kMDPlayer_exhausted;
		//	player->time = MDCalibratorTickToTime(player->calib, MDSequenceGetDuration(MDMergerGetSequence(player->merger)));
		if (tick >= kMDMaxTick)
			tick = MDSequenceGetDuration(sequence);
		player->time = MDCalibratorTickToTime(player->calib, tick);
		return -1;
	} else {
		next_time = MDCalibratorTickToTime(player->calib, tick + 1);
		next_time -= (now_time + kMDPlayerPrefetchInterval);
		if (next_time < kMDPlayerMinimumInterval)
			next_time = kMDPlayerMinimumInterval;
		if (next_time < last_time - now_time)
			next_time = last_time - now_time;
		return next_time;
	}
}

#if !USE_TIME_MANAGER
void *
MyThreadFunc(void *param)
{
	MDPlayer *player = (MDPlayer *)param;
	long time_to_wait;
	while (player->status == kMDPlayer_playing && player->shouldTerminate == 0) {
		time_to_wait = MyTimerFunc(player);
		if (time_to_wait < 0)
			break;
		while (time_to_wait > 0 && player->shouldTerminate == 0) {
			/*  Check every 100ms whether the player should terminate  */
			long n = (time_to_wait > kMDPlayerMaximumInterval * 2 ? kMDPlayerMaximumInterval : time_to_wait);
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
	long time_to_wait;
	time_to_wait = MyTimerFunc(((MyTMTask *)tmTaskPtr)->player);
	if (time_to_wait > 0)
	PrimeTimeTask((QElemPtr)tmTaskPtr, -time_to_wait);
}
#endif

static void
StopSoundInAllTracks(MDPlayer *inPlayer)
{
	int n, track, num;
	MDDestinationInfo *info;
	unsigned char buf[6];

	if (inPlayer == NULL)
		return;

	/*  Dispose the already scheduled MIDI events  */
	for (n = inPlayer->destNum - 1; n >= 0; n--) {
		info = inPlayer->destInfo[n];
		if (info != NULL && info->eref != NULL) {
			MIDIFlushOutput(info->eref);
		}
	}
	
	/*  Dispose the pending note-offs  */
	if (inPlayer->noteOff != NULL) {
		MDTrackClear(inPlayer->noteOff);
		inPlayer->noteOffTick = kMDMaxTick;
	}
	
	/*  Send AllNoteOff (Bn 7B 00) and AllSoundOff (Bn 78 00) to all tracks  */
    num = MDSequenceGetNumberOfTracks(MDMergerGetSequence(inPlayer->merger));
	for (track = 0; track < inPlayer->trackNum; track++) {
		n = inPlayer->destIndex[track];
		if (n < 0 || (info = inPlayer->destInfo[n]) == NULL)
			continue;
		info->packetPtr = MIDIPacketListInit(&info->packetList);
        buf[0] = 0xB0 + inPlayer->destChannel[track];
		buf[1] = 0x7B;
		buf[2] = 0;
		buf[3] = 0xB0 + inPlayer->destChannel[track];
		buf[4] = 0x78;
		buf[5] = 0;
		info->packetPtr = MIDIPacketListAdd(&info->packetList, sizeof(info->packetList), info->packetPtr, 0, 6, (Byte *)buf);
		MIDISend(sMIDIOutputPortRef, info->eref, &info->packetList);
	}
}

int
MDPlayerSendRawMIDI(MDPlayer *player, const unsigned char *p, int size, int destDevice, MDTimeType scheduledTime)
{
	MIDIObjectType objType;
	MIDIObjectRef	eref;
	MIDIPacketList	packetList;
	MIDIPacket *	packetPtr;
	OSStatus sts;
	MIDITimeStamp timeStamp;

	if (destDevice < 0 || destDevice >= sDeviceInfo.destNum)
		return -1;
	
	if (MIDIObjectFindByUniqueID(sDeviceInfo.dest[destDevice].uniqueID, &eref, &objType) != noErr || objType != kMIDIObjectType_Destination)
		return -1;
	if (player != NULL && scheduledTime >= 0)
		timeStamp = ConvertMDTimeTypeToHostTime(scheduledTime + player->startTime);
	else timeStamp = 0;
	packetPtr = MIDIPacketListInit(&packetList);
	packetPtr = MIDIPacketListAdd(&packetList, sizeof(packetList), packetPtr, timeStamp, size, (Byte *)p);
	sts = MIDISend(sMIDIOutputPortRef, (MIDIEndpointRef)eref, &packetList);
	return sts;
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

		player->merger = MDMergerNew(inSequence);
		if (player->merger == NULL)
            goto error;

		player->calib = MDCalibratorNew(inSequence, NULL, kMDEventTempo, -1);
		if (player->calib == NULL)
            goto error;
		MDCalibratorAppend(player->calib, NULL, kMDEventTimeSignature, -1);

		player->status = kMDPlayer_idle;
		player->time = 0;
		player->startTime = 0;
		player->stopTick = kMDMaxTick;

		player->destInfo = NULL;
		player->destNum = 0;
		player->destIndex = NULL;
        player->destChannel = NULL;
        player->trackAttr = NULL;

		player->noteOff = MDTrackNew();
		if (player->noteOff == NULL)
            goto error;
		
		player->noteOffPtr = MDPointerNew(player->noteOff);
		if (player->noteOffPtr == NULL)
            goto error;
		
	/*	if (gAUGraph == NULL)
			MDPlayerInitMIDIDevices(); */
        
        if (MDPlayerAllocateRecordingBuffer(player) == NULL)
            goto error;
    
        player->tempStorage = (unsigned char *)malloc(256);
        if (player->tempStorage == NULL)
            goto error;
        player->tempStorageSize = 256;
		
	/*	player->audio = MDAudioNew(); */
        
	}
	return player;

    error:
    MDPlayerReleaseRecordingBuffer(player);
    if (player->tempStorage != NULL)
        free(player->tempStorage);
    if (player->noteOffPtr != NULL)
        MDPointerRelease(player->noteOffPtr);
    if (player->noteOff != NULL)
        MDTrackRelease(player->noteOff);
    if (player->calib != NULL)
        MDCalibratorRelease(player->calib);
    if (player->merger != NULL)
        MDMergerRelease(player->merger);
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
	long num;
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
            if (inPlayer->trackAttr != NULL)
                free(inPlayer->trackAttr);
            if (inPlayer->destChannel != NULL)
                free(inPlayer->destChannel);
			if (inPlayer->destIndex != NULL)
				free(inPlayer->destIndex);
			if (inPlayer->merger != NULL)
				MDMergerRelease(inPlayer->merger);
			if (inPlayer->calib != NULL)
				MDCalibratorRelease(inPlayer->calib);
			if (inPlayer->noteOffPtr != NULL)
				MDPointerRelease(inPlayer->noteOffPtr);
			if (inPlayer->noteOff != NULL)
				MDTrackRelease(inPlayer->noteOff);
            MDPlayerReleaseRecordingBuffer(inPlayer);
		/*	if (inPlayer->audio != NULL)
				MDAudioRelease(inPlayer->audio); */
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
	MDStatus result;
	if (inPlayer != NULL && inPlayer->merger != NULL) {
		MDCalibrator *calib;
		if (inPlayer->status == kMDPlayer_playing || inPlayer->status == kMDPlayer_exhausted)
			MDPlayerStop(inPlayer);
		calib = MDCalibratorNew(inSequence, NULL, kMDEventTempo, -1);
		if (calib == NULL)
			return kMDErrorOutOfMemory;
		MDCalibratorRelease(inPlayer->calib);
		inPlayer->calib = calib;
		result = MDMergerSetSequence(inPlayer->merger, inSequence);
		if (result == kMDNoError) {
			inPlayer->time = 0;
			inPlayer->startTime = 0;
		}
		return result;
	} else return kMDNoError;
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
    long n, num, i, dev, origDestNum;
	int status;
    long *temp;
    MDSequence *sequence;
	MDTickType oldTick;

    if (inPlayer == NULL || inPlayer->merger == NULL || (sequence = MDMergerGetSequence(inPlayer->merger)) == NULL)
        return kMDNoError;
	
	oldTick = MDCalibratorTimeToTick(inPlayer->calib, inPlayer->time);

	MDMergerReset(inPlayer->merger);

    num = MDSequenceGetNumberOfTracks(sequence);
	inPlayer->trackNum = num;
    inPlayer->destIndex = (long *)re_malloc(inPlayer->destIndex, num * sizeof(long));
    if (inPlayer->destIndex == NULL)
        return kMDErrorOutOfMemory;
    inPlayer->destChannel = (unsigned char *)re_malloc(inPlayer->destChannel, num * sizeof(unsigned char));
    if (inPlayer->destChannel == NULL)
        return kMDErrorOutOfMemory;
    inPlayer->trackAttr = (MDTrackAttribute *)re_malloc(inPlayer->trackAttr, num * sizeof(MDTrackAttribute));
    if (inPlayer->trackAttr == NULL)
        return kMDErrorOutOfMemory;

    temp = (long *)malloc(num * sizeof(long));
    if (temp == NULL)
        return kMDErrorOutOfMemory;

	MDSequenceLock(sequence);
	    
	for (i = 0; i < inPlayer->destNum; i++)
        temp[i] = inPlayer->destInfo[i]->dev;
    origDestNum = inPlayer->destNum;

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
    /*  Allocate destInfo[]  */
    inPlayer->destInfo = (MDDestinationInfo **)re_malloc(inPlayer->destInfo, inPlayer->destNum * sizeof(MDDestinationInfo *));
    if (inPlayer->destInfo == NULL) {
        status = kMDErrorOutOfMemory;
	} else {
		for (i = origDestNum; i < inPlayer->destNum; i++)
			inPlayer->destInfo[i] = MDPlayerNewDestinationInfo(temp[i]);
		
		MDPlayerJumpToTick(inPlayer, oldTick);
		status = kMDNoError;
	}

	MDSequenceUnlock(sequence);

    return status;
}

/* --------------------------------------
	･ MDPlayerJumpToTick
   -------------------------------------- */
MDStatus
MDPlayerJumpToTick(MDPlayer *inPlayer, MDTickType inTick)
{
	if (inPlayer->status == kMDPlayer_playing || inPlayer->status == kMDPlayer_exhausted)
		MDPlayerStop(inPlayer);
	MDMergerJumpToTick(inPlayer->merger, inTick);
	MDCalibratorJumpToTick(inPlayer->calib, inTick);
/*	inPlayer->tick = inTick;  */
	inPlayer->time = MDCalibratorTickToTime(inPlayer->calib, inTick);
	inPlayer->status = kMDPlayer_ready;
	MDTrackClear(inPlayer->noteOff);
	inPlayer->noteOffTick = kMDMaxTick;
	inPlayer->lastTick = kMDNegativeTick;


	return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerPreroll
   -------------------------------------- */
MDStatus
MDPlayerPreroll(MDPlayer *inPlayer, MDTickType inTick, int backtrack)
{
    long n;
/*	long i, num, dev, *temp; */
	MDSequence *sequence;
    MDStatus sts;
	if (inPlayer != NULL && inPlayer->merger != NULL) {

		sequence = MDMergerGetSequence(inPlayer->merger);		
	
		MDPlayerJumpToTick(inPlayer, inTick);

        /*  Release old destination infos  */
        if (inPlayer->destInfo != NULL) {
            for (n = 0; n < inPlayer->destNum; n++) {
                MDPlayerReleaseDestinationInfo(inPlayer->destInfo[n]);
                inPlayer->destInfo[n] = NULL;
            }
        }
        inPlayer->destNum = 0;

		if (sequence != NULL) {
            sts = MDPlayerRefreshTrackDestinations(inPlayer);
            if (sts != kMDNoError)
                return sts;

			/*  Backtrack earlier events  */
			if (inTick > 0 && backtrack) {
				static long sEventType[] = {
					kMDEventSysex, kMDEventSysexCont, kMDEventKeyPres,
					((0 << 16) + kMDEventControl), ((6 << 16) + kMDEventControl),
					((32 << 16) + kMDEventControl), ((100 << 16) + kMDEventControl),
					((101 << 16) + kMDEventControl), ((98 << 16) + kMDEventControl),
					((99 << 16) + kMDEventControl),
					-1 };
				static long sEventLastOnly[] = {
					kMDEventPitchBend, kMDEventChanPres, kMDEventProgram,
					((0xffff << 16) | kMDEventControl),
					-1 };
				MDPlayerBacktrackEvents(inPlayer, sEventType, sEventLastOnly);
			}
			
			/*  Prepare metronome  */
			PrepareMetronomeForTick(inPlayer, inTick);
			
			inPlayer->status = kMDPlayer_suspended;

		}
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
	MDSequence *sequence;

	if (inPlayer == NULL || inPlayer->merger == NULL)
		return kMDNoError;
	if (inPlayer->status == kMDPlayer_playing)
		return kMDNoError;

	sequence = MDMergerGetSequence(inPlayer->merger);
	
//	if (inPlayer->status != kMDPlayer_suspended) {
//		MDPlayerPreroll(inPlayer, 0, 0);
//	}
	if (inPlayer->status != kMDPlayer_suspended)
		MDPlayerPreroll(inPlayer, MDCalibratorTimeToTick(inPlayer->calib, inPlayer->time), 0);
	
	/*  Schedule special events  */
	{
		MDEvent anEvent;
		MDTickType tick, duration;
		duration = MDSequenceGetDuration(sequence);
		MDSetKind(&anEvent, kMDEventSpecial);
		if (inPlayer->stopTick < kMDMaxTick) {
			MDSetCode(&anEvent, kMDSpecialStopPlaying);
			MDSetTick(&anEvent, inPlayer->stopTick);
			RegisterEventInNoteOffTrack(inPlayer, &anEvent);
		}
		if (inPlayer->isRecording)
			tick = kMDMaxTick - 1;  /* Don't stop at the end of sequence  */
		else tick = duration;
		MDSetCode(&anEvent, kMDSpecialEndOfSequence);
		MDSetTick(&anEvent, tick);
		RegisterEventInNoteOffTrack(inPlayer, &anEvent);
	}
	
	if (MDSequenceCreateMutex(sequence))
		return kMDErrorOnSequenceMutex;
	
	inPlayer->startTime = GetHostTimeInMDTimeType() - inPlayer->time;
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
	･ MDPlayerStop
   -------------------------------------- */
MDStatus
MDPlayerStop(MDPlayer *inPlayer)
{
	if (inPlayer == NULL || inPlayer->merger == NULL)
		return kMDNoError;
	if (inPlayer->status == kMDPlayer_suspended) {
		inPlayer->stopTick = kMDMaxTick;
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
	
	MDSequenceDisposeMutex(MDMergerGetSequence(inPlayer->merger));
	
	
	/*  Send AllNoteOff (Bn 7B 00) and AllSoundOff (Bn 78 00)  */
/*	{
		static unsigned char sAllNoteAndSoundOff[] = {0xB0, 0x7B, 0x00, 0xB0, 0x78, 0x00};
		MDTimeType lastTime = MDCalibratorTickToTime(inPlayer->calib, inPlayer->lastTick);
		SendMIDIEventsToAllTracks(inPlayer, lastTime, 6, sAllNoteAndSoundOff);
	} */
	StopSoundInAllTracks(inPlayer);
	
	inPlayer->status = kMDPlayer_ready;

	inPlayer->stopTick = kMDMaxTick;
	
    return kMDNoError;
}

/* --------------------------------------
	･ MDPlayerScheduleStopTick
   -------------------------------------- */
MDStatus
MDPlayerScheduleStopTick(MDPlayer *inPlayer, MDTickType inStopTick)
{
	/*  Note: stop tick will be reset every time MDPlayerStop() is called  */
	if (inPlayer != NULL)
		inPlayer->stopTick = inStopTick;
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
		if (inPlayer->status == kMDPlayer_playing) {
			return GetHostTimeInMDTimeType() - inPlayer->startTime;
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
MDPlayerSetMIDIThruDeviceAndChannel(long dev, int ch)
{
    if (dev >= 0 && dev < MDPlayerGetNumberOfDestinations()) {
		MIDIObjectType objType;
		MIDIObjectRef eref;
        sMIDIThruDevice = dev;
		if (MIDIObjectFindByUniqueID(sDeviceInfo.dest[dev].uniqueID, &eref, &objType) == noErr && objType == kMIDIObjectType_Destination)
			sMIDIThruDeviceRef = eref;
		else sMIDIThruDeviceRef = NULL;
    /*    sMIDIThruDeviceRef = MIDIGetDestination(dev); */
        sMIDIThruChannel = ch;  /*  If 16, then incoming channel is kept  */
    } else {
        sMIDIThruDevice = -1;
        sMIDIThruDeviceRef = NULL;
    }
}

/* --------------------------------------
	･ MDPlayerBacktrackEvents
   -------------------------------------- */
MDStatus
MDPlayerBacktrackEvents(MDPlayer *inPlayer, const long *inEventType, const long *inEventTypeLastOnly)
{
	/*  The long values in inEventType[] and inEventTypeLastOnly[] are in the following format:
		lower 16 bits = MDEventKind, upper 16 bits = the 'code' field in MDEvent record.
		The value -1 is used for termination.  */
	
	typedef struct EventWithDest {
		MDEvent *ep;
		long	dest;
	} EventWithDest;
	EventWithDest *eventWithDestList;
	MDEvent *ep;
	long num, n, dest, index, track, maxIndex;
	MDMerger *merger;
	MDDestinationInfo *info;
	static const long sDefaultEventType[] = {-1};

	if (inEventType == NULL)
		inEventType = sDefaultEventType;
	if (inEventTypeLastOnly == NULL)
		inEventTypeLastOnly = sDefaultEventType;
	merger = MDMergerDuplicate(inPlayer->merger);
	if (merger == NULL)
		return kMDErrorOutOfMemory;

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
				long len = 1;  /*  Include the first 0xf0 byte  */
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
			MDSetTick(&tempEvent, MDCalibratorTimeToTick(inPlayer->calib, timeStamp));
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

