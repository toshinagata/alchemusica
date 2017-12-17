/*
   MDSequenceSMF.c
   Created by Toshi Nagata, 2000.11.24.

   Copyright (c) 2000-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#include "MDHeaders.h"

#include <stdlib.h>		/*  for malloc(), realloc(), and free()  */
#include <string.h>		/*  for memset()  */
#include <stdio.h>
#include <ctype.h>

#define DEBUG_PRINT	0

/*  An internal struct for converting SMF to MD format  */
typedef struct MDSMFConvert		MDSMFConvert;
struct MDSMFConvert {
	/*  The information for the whole sequence  */
	STREAM			stream;
	MDSequence *	sequence;		/*  the resulting sequence  */
	int32_t			timebase;		/*  the SMF timebase  */
	int32_t			max_tick;		/*  the maximum tick (the length of the sequence)  */
	int32_t			trkno;			/*  the number of tracks  */

	/*  The information for each track  */
	MDTrack *		temptrk;		/*  the current track  */
	int32_t			track_index;	/*  the current track number  */
	int32_t			tick;			/*  the tick of the last event  */
	int32_t			deltatime;		/*  the deltatime of the current event  */
	unsigned char	status;			/*  running status  */
    unsigned char	track_channel;	/*  track channel (16 if the sequence is multi-track mode)  */
	int32_t			pos;			/*  the file position where the track size is to be written  */

	MDSequenceCallback callback;	/*  A callback function. Periodically called, and abort if 0 */
	int32_t			filesize;		/*  total file size  */
	void *			cbdata;			/*  callback data  */
};

/*  SMF コントロールで特別扱いするもの  */
enum {
	kMDEventSMFBankSelectMSB	= 0,
	kMDEventSMFDataEntryMSB		= 6,
	kMDEventSMFBankSelectLSB	= 32,
	kMDEventSMFDataEntryLSB		= 38,
	kMDEventSMFDataIncrement	= 96,
	kMDEventSMFDataDecrement	= 97,
	kMDEventSMFNRPNLSB			= 98,
	kMDEventSMFNRPNMSB			= 99,
	kMDEventSMFRPNLSB			= 100,
	kMDEventSMFRPNMSB			= 101
};

#define kMDMaxSMFTempo	16777215		/* 2^24 - 1 */

static int32_t
MDSequenceTempoToSMFTempo(float tempo)
{
    if (tempo < kMDMinTempo)
        return kMDMaxSMFTempo;
    if (tempo > kMDMaxTempo)
        return (int32_t)(60000000.0 / kMDMaxTempo);
    else return (int32_t)(60000000.0 / tempo);
}

static int32_t
MDSequenceSMFTempoToTempo(int32_t smfTempo)
{
    if (smfTempo <= (int32_t)(60000000.0 / kMDMaxTempo))
        return kMDMaxTempo;
    else if (smfTempo > (int32_t)(60000000.0 / kMDMinTempo))
        return kMDMinTempo;
    else return (float)(60000000.0 / smfTempo);
}

#pragma mark ====== Reading SMF ======

static MDStatus	
MDSequenceReadSMFReadMessage(MDSMFConvert *cref, MDEvent *eref)
{
	int32_t length;
	unsigned char *msg;

	/*  Read the message length  */
	if (MDReadStreamFormat(cref->stream, "w", &length) != 1)
		return kMDErrorUnexpectedEOF;

	/*  Allocate the memory  */
	/*  For kMDEventSysex, append the beginning 'F0'. */
	if (MDGetKind(eref) == kMDEventSysex)
		length++;
	if (MDSetMessageLength(eref, length) < 0)
		return kMDErrorOutOfMemory;
	
	msg = MDGetMessagePtr(eref, NULL);
	if (MDGetKind(eref) == kMDEventSysex) {
		msg[0] = 0xf0;
		if (FREAD_(msg + 1, length - 1, cref->stream) < length - 1)
			return kMDErrorUnexpectedEOF;
	} else {
		/*  For messages other than Sysex, the data can be always treated as a C string
			as MDSetMessageLength() automatically appends a terminating null byte  */
		if (FREAD_(msg, length, cref->stream) < length)
			return kMDErrorUnexpectedEOF;
	}
	return kMDNoError;
}

/*  Read one meta event  */
static MDStatus
MDSequenceReadSMFMetaEvent(MDSMFConvert *cref, MDEvent *eref)
{
	MDStatus result = kMDNoError;
	int32_t length;
	int n;
	unsigned char s[8], *metaDataPtr;
	
	n = GETC(cref->stream);
	if (n == EOF)
		return kMDErrorUnexpectedEOF;
	MDSetCode(eref, n);

	switch (n) {
		case kMDMetaEndOfTrack:
			if (cref->max_tick < cref->tick)
				cref->max_tick = cref->tick;
			/*  Read the message length (should be always zero, but not checked)  */
			if (MDReadStreamFormat(cref->stream, "w", &length) != 1) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eref, kMDEventStop);
			break;
		case kMDMetaDuration: {
			MDTickType duration;
			MDSetKind(eref, kMDEventInternalDuration);
			if (MDReadStreamFormat(cref->stream, "ww", &length, &duration) != 2) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetDuration(eref, duration);
			break;
		}
		case kMDMetaPortNumber:
		case kMDMetaTempo:
		case kMDMetaSMPTE:
		case kMDMetaTimeSignature:
		case kMDMetaKey:
			MDSetKind(eref, kMDEventMeta);
			if (MDReadStreamFormat(cref->stream, "w", &length) != 1) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			if (length >= 8) {
				result = kMDErrorWrongMetaEvent;
				break;
			}
			memset(s, 0, sizeof(s));
			if (FREAD_(s, length, cref->stream) < length) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			metaDataPtr = MDGetMetaDataPtr(eref);
			if (n == kMDMetaPortNumber) {
				MDSetKind(eref, kMDEventPortNumber);
				MDSetData1(eref, s[0]);
			} else if (n == kMDMetaTempo) {
				MDSetKind(eref, kMDEventTempo);
				MDSetTempo(eref, MDSequenceSMFTempoToTempo(s[0] * 65536.0f + s[1] * 256.0f + s[2]));
			} else if (n == kMDMetaSMPTE) {
				MDSMPTERecord *smp = MDGetSMPTERecordPtr(eref);
				MDSetKind(eref, kMDEventSMPTE);
				smp->hour = s[0];
				smp->min = s[1];
				smp->sec = s[2];
				smp->frame = s[3];
				smp->subframe = s[4];
			} else if (n == kMDMetaTimeSignature) {
				MDSetKind(eref, kMDEventTimeSignature);
				metaDataPtr[0] = s[0];
				metaDataPtr[1] = s[1];
				metaDataPtr[2] = s[2];
				metaDataPtr[3] = s[3];
			} else if (n == kMDMetaKey) {
				MDSetKind(eref, kMDEventKey);
				metaDataPtr[0] = s[0];
				metaDataPtr[1] = s[1];
			} else {
				result = kMDErrorWrongMetaEvent;
				break;
			}
			break;
		case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8:
		case 9: case 10: case 11: case 12: case 13: case 14: case 15:
		/*  code 1-15 are reserved for various meta events  */
			MDSetKind(eref, kMDEventMetaText);
			result = MDSequenceReadSMFReadMessage(cref, eref);
			break;				
		default:
			MDSetKind(eref, kMDEventMetaMessage);
			result = MDSequenceReadSMFReadMessage(cref, eref);
			break;
	}
	return result;
}

static int
MDSequenceReadOneChar(void *ptr)
{
    return GETC((STREAM)ptr);
}

/*  Read one channel event. n is the first byte (status byte, or the first data
    byte if running status is used)  */
static MDStatus
MDSequenceReadSMFChannelEvent(MDSMFConvert *cref, MDEvent *eref, int n)
{
    return MDEventFromMIDIMessage(eref, n, cref->status, MDSequenceReadOneChar, cref->stream, &(cref->status));

#if 0
	MDStatus result = kMDNoError;
	int data1, data2;
	unsigned char ch;		/*  MIDI channel  */

	/*  Get the status byte  */
	if (n < 0x80) {
		/*  running status  */
		data1 = n;
		n = cref->status;
	} else {
		cref->status = n;
		data1 = GETC(cref->stream);
		if (data1 == EOF)
			return kMDErrorUnexpectedEOF;
	}

	/*  Get the MD track number  */
	ch = (n & 0x0f);	/*  MIDI channel  */
	MDSetChannel(eref, ch);
	
	switch (n & 0xf0) {
		case kMDEventSMFNoteOff:
		case kMDEventSMFNoteOn:
			data2 = GETC(cref->stream);
			if (data2 == EOF) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			data2 &= 0xff;
			if ((n & 0xf0) == kMDEventSMFNoteOn && data2 != 0) {
				/*  Note on  */
                MDSetKind(eref, kMDEventNote);
                MDSetCode(eref, data1);
                MDSetNoteOnVelocity(eref, data2);
                MDSetNoteOffVelocity(eref, 0);
                MDSetDuration(eref, 0); /* Set temporary duration: 0 indicates "note-on that is not paired yet" */
			} else {
				/*  Note off  */
                MDSetKind(eref, kMDEventInternalNoteOff);
                MDSetCode(eref, data1);
                MDSetNoteOnVelocity(eref, 0);
                MDSetNoteOffVelocity(eref, data2);
			}
			break;
		case kMDEventSMFKeyPressure:
			data2 = GETC(cref->stream);
			if (data2 == EOF) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eref, kMDEventKeyPres);
			MDSetCode(eref, data1);
			MDSetData1(eref, data2);
			break;
		case kMDEventSMFControl:
			data2 = GETC(cref->stream);
			if (data2 == EOF) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eref, kMDEventControl);
			MDSetCode(eref, data1);
			MDSetData1(eref, data2);
			break;
		case kMDEventSMFProgram:
			MDSetKind(eref, kMDEventProgram);
			MDSetData1(eref, data1);
			break;
		case kMDEventSMFChannelPressure:
			MDSetKind(eref, kMDEventChanPres);
			MDSetData1(eref, data1);
			break;
		case kMDEventSMFPitchBend:
			data2 = GETC(cref->stream);
			if (data2 == EOF) {
				result = kMDErrorUnexpectedEOF;
				break;
			}
			MDSetKind(eref, kMDEventPitchBend);
			MDSetData1(eref, ((data1 & 0x7f) + ((data2 & 0x7f) << 7)) - 8192);
			break;
		default:
			result = kMDErrorUnknownChannelEvent;
			break;
	} /* end switch */

	return result;
#endif
}

/*  Read one SMF track  */
static MDStatus
MDSequenceReadSMFTrack(MDSMFConvert *cref)
{
	MDEvent event;
	MDStatus result = kMDNoError;
	MDPointer *ptr;
	int n, count;
	unsigned char quitFlag, skipFlag;
	MDTickType maxTick = 0;
	MDTickType metaDuration = 0;
//	MDTrack *noteOffTrack;
//	MDPointer *noteOffPtr;

	/*  Initialize track info  */
	cref->tick = 0;
	cref->deltatime = 0;

	cref->temptrk = MDTrackNew();
	if (cref->temptrk == NULL)
		return kMDErrorOutOfMemory;

	ptr = MDPointerNew(cref->temptrk);
	if (ptr == NULL)
		return kMDErrorOutOfMemory;

//	noteOffTrack = MDTrackNew();
//	if (noteOffTrack == NULL)
//		return kMDErrorOutOfMemory;
//	noteOffPtr = MDPointerNew(noteOffTrack);
//	if (noteOffPtr == NULL)
//		return kMDErrorOutOfMemory;

	quitFlag = 0;
	MDEventInit(&event);
	count = 0;

	while (quitFlag == 0) {
	
		if (++count >= 1000) {
			if (cref->callback != NULL) {
				n = (*cref->callback)((float)FTELL(cref->stream) / cref->filesize * 100, cref->cbdata);
				if (n == 0) {
					result = kMDErrorUserInterrupt;
					break;
				}
			}
			count = 0;
		}
		
		/*  Read the delta time  */
		if (MDReadStreamFormat(cref->stream, "w", &cref->deltatime) != 1) {
			result = kMDErrorUnexpectedEOF;
			break;
		}
		
		cref->tick += cref->deltatime;
		MDSetTick(&event, cref->tick);
		MDSetChannel(&event, 0);
		skipFlag = 0;

		/*  Read the status byte  */
		n = GETC(cref->stream);
		if (n == EOF) {
			result = kMDErrorUnexpectedEOF;
			break;
		}

		if (n == kMDEventSMFSysex) {				/*  sysex events  */
			MDSetKind(&event, kMDEventSysex);
			MDSetChannel(&event, 16);
			result = MDSequenceReadSMFReadMessage(cref, &event);
		} else if (n == kMDEventSMFSysexF7) {		/*  sysex events (continued)  */
			MDSetKind(&event, kMDEventSysexCont);
			MDSetChannel(&event, 16);
			result = MDSequenceReadSMFReadMessage(cref, &event);
		} else if (n == kMDEventSMFMeta) {			/*  meta events  */
			MDSetChannel(&event, 17);				/*  not a MIDI event  */
			result = MDSequenceReadSMFMetaEvent(cref, &event);
			if (MDGetKind(&event) == kMDEventStop) {
				skipFlag = quitFlag = 1;
			} else if (MDGetKind(&event) == kMDEventMetaText) {
                char buf[256];
                switch (MDGetCode(&event)) {
                    case kMDMetaSequenceName:
                        MDTrackGetName(cref->temptrk, buf, sizeof buf);
                        if (buf[0] == 0) {
                            result = MDTrackSetName(cref->temptrk, (const char *)MDGetMessageConstPtr(&event, NULL));
                            skipFlag = 1;
                        }
                        break;
                    case kMDMetaDeviceName:
                        MDTrackGetDeviceName(cref->temptrk, buf, sizeof buf);
                        if (buf[0] == 0) {
                            result = MDTrackSetDeviceName(cref->temptrk, (const char *)MDGetMessageConstPtr(&event, NULL));
                            skipFlag = 1;
                        }
                        break;
                }
            } else if (MDGetKind(&event) == kMDEventInternalDuration) {
				metaDuration = MDGetDuration(&event);
				skipFlag = 1;
			}
		} else {	/*  channel events */
			result = MDSequenceReadSMFChannelEvent(cref, &event, n);
		}
		
		if (result != kMDNoError)
			break;
		
		if (MDGetKind(&event) == kMDEventInternalNoteOn) {
			if (metaDuration > 0)
				MDSetDuration(&event, metaDuration);
		} else if (MDGetKind(&event) == kMDEventInternalNoteOff) {
			result = MDTrackMatchNoteOff(cref->temptrk, &event);
			if (result != kMDNoError) {
				fprintf(stderr, "Corrupsed file? orphaned note off at %d\n", (int32_t)MDGetTick(&event));
				// break;
			}
			skipFlag = 1;
			/*  Register note-off into the separate track  */
        /*    dprintf(2, "Note-off event encountered: tick %ld code %d vel %d\n", MDGetTick(&event), MDGetCode(&event), MDGetNoteOffVelocity(&event));
			if (MDTrackAppendEvents(noteOffTrack, &event, 1) < 1) {
				result = kMDErrorOutOfMemory;
				break;
			}
			skipFlag = 1; */
		}
		metaDuration = 0;

		if (!skipFlag) {
			if (MDTrackAppendEvents(cref->temptrk, &event, 1) < 1) {
				result = kMDErrorOutOfMemory;
				break;
			}

	#if DEBUG_PRINT
	{
		char buf[1024];
		printf("%s\n", MDEventToString(&event, buf, sizeof buf));
	}
	#endif

		}
		MDEventClear(&event);
	} /* end while (quitFlag == 0)  */
	
	/*  Set the track duration  */
	if (maxTick < cref->tick)
		maxTick = cref->tick;
	MDTrackSetDuration(cref->temptrk, maxTick);

    /*  Match the note-on/note-off pairs  */
/*    result = MDTrackMatchNoteOffInTrack(cref->temptrk, noteOffTrack); */

	if (result == kMDNoError) {
        char buf[256];
		/*  Guess track name  */
        MDTrackGetName(cref->temptrk, buf, sizeof buf);
        if (buf[0] == 0) {
            MDTrackGuessName(cref->temptrk, buf, 256);
            result = MDTrackSetName(cref->temptrk, buf);
        }
    }
	if (result == kMDNoError) {
        char buf[256];
		/*  Guess device name  */
        MDTrackGetDeviceName(cref->temptrk, buf, sizeof buf);
        if (buf[0] == 0) {
            MDTrackGuessDeviceName(cref->temptrk, buf, 256);
            result = MDTrackSetDeviceName(cref->temptrk, buf);
        }
		/*  Guess the device number from the device name  */
		MDTrackSetDevice(cref->temptrk, MDPlayerGetDestinationNumberFromName(buf));
    }
	
	if (result != kMDErrorOutOfMemory) {
		MDPointerRelease(ptr);
		MDSequenceInsertTrack(cref->sequence, -1, cref->temptrk);
		MDTrackRelease(cref->temptrk);  /* the track will be retained by the sequence */
		cref->temptrk = NULL;
	}
	
//	MDPointerRelease(noteOffPtr);
//	MDTrackRelease(noteOffTrack);

	return result;
}

MDStatus
MDSequenceReadSMF(MDSequence *inSequence, STREAM stream, MDSequenceCallback callback, void *cbdata)
{
	MDStatus result = kMDNoError;
	MDSMFConvert conv;
	short fmt, trkno, timebase;		/*  SMF format, track number, timebase  */
	int32_t size, pos;
	char tag[8];
	
	if (inSequence == NULL || stream == NULL)
		return kMDErrorInternalError;

	/*  Initialize the convert record  */
	memset(&conv, 0, sizeof(conv));
	conv.stream = stream;
	conv.sequence = inSequence;
	conv.callback = callback;
	pos = (int32_t)FTELL(stream);
	FSEEK(stream, 0, SEEK_END);
    conv.track_channel = 0;  /*  Not to be used  */
	conv.filesize = (int32_t)FTELL(stream) - pos;
	conv.cbdata = cbdata;
	FSEEK(stream, pos, SEEK_SET);
	
	/*  Read the file header */
	if (MDReadStreamFormat(conv.stream, "A4Nn3", tag, &size, &fmt, &trkno, &timebase) == 5
	&& size == 6 && strcmp(tag, "MThd") == 0) {
		if (fmt != 0 && fmt != 1) {
			result = kMDErrorUnsupportedSMFFormat;
		} else {
			conv.timebase = timebase;
			conv.trkno = trkno;
			MDSequenceSetTimebase(inSequence, timebase);
		}
	} else {
		result = kMDErrorHeaderChunkNotFound;
	}
	
	/*  Read each track  */
	while (result == kMDNoError && MDReadStreamFormat(conv.stream, "A4N", tag, &size) == 2) {
		/*  Check the tag  */
		if (strcmp(tag, "MTrk") == 0) {
			result = MDSequenceReadSMFTrack(&conv);
			if (result != kMDErrorOutOfMemory)
				conv.track_index++;
			else break;
			if (--trkno <= 0)
				break;
		} else {
			/*  Skip this block  */
			FSEEK(stream, size, SEEK_CUR);
		}
	}
	conv.trkno = conv.track_index;

#if DEBUG_PRINT
	{	/*  for debug  */
		int i;
		char buf[1024];
	/*	MDTrackPrintOneEvent(NULL, NULL); */
		for (i = 0; i < MDSequenceGetNumberOfTracks(inSequence); i++) {
			MDPointer *ptr;
			MDEvent *ev;
			MDTrack *track;
			track = MDSequenceGetTrack(inSequence, i);
			ptr = MDPointerNew(track);
			while ((ev = MDPointerForward(ptr)) != NULL) {
				printf("%ld: %s\n", (int32_t)MDPointerGetPosition(ptr), MDEventToString(ev, buf, sizeof buf));
			}
			MDPointerRelease(ptr);
		}
	/*	MDTrackPrintOneEvent((MDEvent *)(-1), NULL); */
	}
#endif

	return result;
}

#pragma mark ====== Writing SMF ======

static MDStatus
MDSequenceWriteSMFDeltaTime(MDSMFConvert *cref, MDTickType tick)
{
	cref->deltatime = tick - cref->tick;
	if (MDWriteStreamFormat(cref->stream, "w", cref->deltatime) != 1)
		return kMDErrorCannotWriteToStream;
	cref->tick += cref->deltatime;
	return kMDNoError;
}

static MDStatus	
MDSequenceWriteSMFWriteMessage(MDSMFConvert *cref, const unsigned char *p, int32_t length)
{
	/*  Write the message length  */
	if (MDWriteStreamFormat(cref->stream, "w", length) != 1)
		return kMDErrorCannotWriteToStream;

	/*  Write the message body  */
	if (FWRITE_(p, length, cref->stream) < length)
		return kMDErrorCannotWriteToStream;
	return kMDNoError;
}

/*  Write a special "duration" event  */
static MDStatus
MDSequenceWriteSMFSpecialDurationEvent(MDSMFConvert *cref, MDEvent *eref)
{
	MDTickType d;
	int i;
	unsigned char s[12];

	if (MDGetKind(eref) != kMDEventNote)
		return kMDErrorInternalError;

	/*  Convert the duration to BER-compressed form  */
	d = MDGetDuration(eref);
	i = sizeof(s) - 1;
	s[i] = (d & 0x7f);
	while (i > 4) {
		d >>= 7;
		if (d == 0)
			break;
		s[--i] = ((d & 0x7f) | 0x80);
	}
	s[i - 1] = sizeof(s) - i;  /*  Message length  */
	i--;
	s[--i] = kMDMetaDuration;
	s[--i] = kMDEventSMFMeta;
/*	s[--i] = 0;  *//*  delta time  */

	if (FWRITE_(s + i, sizeof(s) - i, cref->stream) < sizeof(s) - i)
		return kMDErrorCannotWriteToStream;

	return kMDNoError;
}

/*  Write one meta event  */
static MDStatus
MDSequenceWriteSMFMetaEvent(MDSMFConvert *cref, MDEvent *eref)
{
	int32_t length;
	int n;
	unsigned char s[8], *metaDataPtr;
	const unsigned char *p;
	MDEventKind kind = MDGetKind(eref);

	n = PUTC(kMDEventSMFMeta, cref->stream);
	if (n == EOF)
		return kMDErrorCannotWriteToStream;
	
	switch (kind) {
		case kMDEventMetaText:
		case kMDEventMetaMessage:
			n = PUTC(MDGetCode(eref), cref->stream);
			if (n == EOF)
				return kMDErrorCannotWriteToStream;
			else {
				p = MDGetMessageConstPtr(eref, &length);
				return MDSequenceWriteSMFWriteMessage(cref, p, length);
			}
		case kMDEventTempo: {
			int32_t ntempo;
			ntempo = MDSequenceTempoToSMFTempo(MDGetTempo(eref));
			s[0] = ntempo / 65536;
			s[1] = ntempo / 256;
			s[2] = ntempo;
			n = kMDMetaTempo;
			length = 3;
			break;
		}
		case kMDEventTimeSignature:
			metaDataPtr = MDGetMetaDataPtr(eref);
			n = kMDMetaTimeSignature;
			s[0] = metaDataPtr[0];
			s[1] = metaDataPtr[1];
			s[2] = metaDataPtr[2];
			s[3] = metaDataPtr[3];
			length = 4;
			break;
		case kMDEventKey:
			metaDataPtr = MDGetMetaDataPtr(eref);
			n = kMDMetaKey;
			s[0] = metaDataPtr[0];
			s[1] = metaDataPtr[1];
			length = 2;
			break;
		case kMDEventSMPTE: {
			MDSMPTERecord *smp = MDGetSMPTERecordPtr(eref);
			n = kMDMetaSMPTE;
			s[0] = smp->hour;
			s[1] = smp->min;
			s[2] = smp->sec;
			s[3] = smp->frame;
			s[4] = smp->subframe;
			length = 5;
			break;
		}
		case kMDEventPortNumber:
			n = kMDMetaPortNumber;
			s[0] = MDGetData1(eref);
			length = 1;
			break;
		default:
			return kMDErrorWrongMetaEvent;
	}
	
	if (PUTC(n, cref->stream) == EOF)
		return kMDErrorCannotWriteToStream;

	return MDSequenceWriteSMFWriteMessage(cref, s, length);
}

/*  Write one channel event  */
static MDStatus
MDSequenceWriteSMFChannelEvent(MDSMFConvert *cref, MDEvent *eref)
{
	unsigned char s[4];
	int n;
	int data1;

	s[1] = MDGetCode(eref);
	s[2] = data1 = MDGetData1(eref);
	n = 3;
	switch (MDGetKind(eref)) {
		case kMDEventNote:
			s[0] = kMDEventSMFNoteOn;
			s[2] = MDGetNoteOnVelocity(eref);
            dprintf(2, "kMDEventNote, %02x %02x %02x\n", s[0], s[1], s[2]);
			break;
		case kMDEventInternalNoteOff:
			s[0] = kMDEventSMFNoteOff;
			s[2] = MDGetNoteOffVelocity(eref);
            dprintf(2, "kMDEventInternalNoteOff, %02x %02x %02x\n", s[0], s[1], s[2]);
			break;
		case kMDEventControl:
			s[0] = kMDEventSMFControl;
			break;
		case kMDEventPitchBend:
			s[0] = kMDEventSMFPitchBend;
			s[1] = (data1 & 0x7f);
			s[2] = ((data1 + 8192) >> 7) & 0x7f;
			break;
		case kMDEventProgram:
			s[0] = kMDEventSMFProgram;
			s[1] = data1;
			n = 2;
			break;
		case kMDEventChanPres:
			s[0] = kMDEventSMFChannelPressure;
			s[1] = data1;
			n = 2;
			break;
		case kMDEventKeyPres:
			s[0] = kMDEventSMFKeyPressure;
			break;
		default:
			return kMDErrorUnknownChannelEvent;
	}
	
    if (cref->track_channel < 16)
        s[0] |= cref->track_channel;
    else
        s[0] |= (MDGetChannel(eref) & 0x0f);

	if (FWRITE_(s, n, cref->stream) < n)
		return kMDErrorCannotWriteToStream;
	return kMDNoError;
}

/*  Write sequence name and device information as meta events  */
static MDStatus
MDSequenceWriteSMFTrackNameAndDevice(MDSMFConvert *cref)
{
    MDStatus result;
    char buf[256];
	int32_t dev;

    /*  Sequence name  */
    MDTrackGetName(cref->temptrk, buf, sizeof buf);
    result = MDSequenceWriteSMFDeltaTime(cref, 0);
    if (result != kMDNoError)
        return result;
    if (PUTC(kMDEventSMFMeta, cref->stream) == EOF)
        return kMDErrorCannotWriteToStream;
    if (PUTC(kMDMetaSequenceName, cref->stream) == EOF)
        return kMDErrorCannotWriteToStream;
    result = MDSequenceWriteSMFWriteMessage(cref, (unsigned char *)buf, (int)strlen(buf));
    if (result != kMDNoError)
        return result;

    /*  Device name  */
	dev = MDTrackGetDevice(cref->temptrk);
	if (dev < 0 || MDPlayerGetDestinationName(dev, buf, sizeof buf) != kMDNoError)
		MDTrackGetDeviceName(cref->temptrk, buf, sizeof buf);
    result = MDSequenceWriteSMFDeltaTime(cref, 0);
    if (result != kMDNoError)
        return result;
    if (PUTC(kMDEventSMFMeta, cref->stream) == EOF)
        return kMDErrorCannotWriteToStream;
    if (PUTC(kMDMetaDeviceName, cref->stream) == EOF)
        return kMDErrorCannotWriteToStream;
    result = MDSequenceWriteSMFWriteMessage(cref, (unsigned char *)buf, (int)strlen(buf));
    if (result != kMDNoError)
        return result;
    return result;
}

/*  Write one SMF track  */
static MDStatus
MDSequenceWriteSMFTrackWithSelection(MDSMFConvert *cref, IntGroup *pset, char eotSelected)
{
	MDPointer *ptr;
	MDEvent *eref;
	MDStatus result = kMDNoError;
	MDTrack *noteOffTrack;
	MDPointer *noteOffPtr;
	MDEvent *noteOffRef;
	MDTickType noteOffTick;
	int n, count;
	int32_t nevents;
	int idx;
	const unsigned char sEndOfTrack[3] = { kMDEventSMFMeta, kMDMetaEndOfTrack, 0 };

	/*  Initialize track info  */
	cref->tick = 0;
	cref->deltatime = 0;

	ptr = MDPointerNew(cref->temptrk);
	if (ptr == NULL)
		return kMDErrorOutOfMemory;

	noteOffTrack = MDTrackNew();
	if (noteOffTrack == NULL)
		return kMDErrorOutOfMemory;
	noteOffPtr = MDPointerNew(noteOffTrack);
	if (noteOffPtr == NULL)
		return kMDErrorOutOfMemory;
	noteOffTick = kMDMaxTick;

	count = 0;
	idx = -1;
	if (pset == NULL || pset == (IntGroup *)(-1)) {
		nevents = MDTrackGetNumberOfEvents(cref->temptrk);
		result = MDSequenceWriteSMFTrackNameAndDevice(cref);
		if (result != kMDNoError)
			return result;
	} else
		nevents = IntGroupGetCount(pset);

	while (
		(eref = 
			((pset == NULL || pset == (IntGroup *)(-1))
				? MDPointerForward(ptr) 
				: MDPointerForwardWithPointSet(ptr, pset, &idx)
			)
		) != NULL && MDGetKind(eref) != kMDEventStop) {

		if (MDGetKind(eref) == kMDEventNull) {
			/*  We should not have it, but sometimes we get it because of bugs  */
			continue;
		}
			
		if (++count >= 1000) {
			if (cref->callback != NULL) {
				n = (*cref->callback)(100.0f * (cref->track_index + ((float)MDPointerGetPosition(ptr) / nevents)) / cref->trkno, cref->cbdata);
				if (n == 0) {
					result = kMDErrorUserInterrupt;
					break;
				}
			}
			count = 0;
		}

		/*  Check the note off events and output if necessary  */
		if (noteOffTick <= MDGetTick(eref)) {
			while (1) {
				MDPointerSetPosition(noteOffPtr, 0);
				if ((noteOffRef = MDPointerCurrent(noteOffPtr)) != NULL && MDGetTick(noteOffRef) <= MDGetTick(eref)) {
                    dprintf(2, "a pending note-off output, tick %ld code %d vel %d\n", MDGetTick(noteOffRef), MDGetCode(noteOffRef), MDGetNoteOffVelocity(noteOffRef));
					result = MDSequenceWriteSMFDeltaTime(cref, MDGetTick(noteOffRef));
					if (result == kMDNoError)
						result = MDSequenceWriteSMFChannelEvent(cref, noteOffRef);
					if (result != kMDNoError)
						goto last;
					MDPointerDeleteAnEvent(noteOffPtr, NULL);
                    dprintf(2, "num of pending note-offs = %ld\n", MDTrackGetNumberOfEvents(noteOffTrack));
				} else {
					if (noteOffRef != NULL)
						noteOffTick = MDGetTick(noteOffRef);
					else
						noteOffTick = kMDMaxTick;
					break;
				}
			}
		}

		/*  Write the delta time  */
		result = MDSequenceWriteSMFDeltaTime(cref, MDGetTick(eref));
		if (result != kMDNoError)
			break;

		/*  Write the status byte  */
		if (MDIsSysexEvent(eref)) {					/*  sysex events  */
			const unsigned char *p;
			int32_t length;
			p = MDGetMessageConstPtr(eref, &length);
			if (MDGetKind(eref) == kMDEventSysexCont)
				n = kMDEventSMFSysexF7;
			else {
				n = kMDEventSMFSysex;
				/*  Skip 'F0' at the top  */
				if (*p == 0xf0) {
					p++;
					length--;
				}
			}
			if (PUTC(n, cref->stream) == EOF) {
				result = kMDErrorCannotWriteToStream;
				break;
			}
			result = MDSequenceWriteSMFWriteMessage(cref, p, length);
		} else if (MDIsMetaEvent(eref)) {			/*  meta events  */
			result = MDSequenceWriteSMFMetaEvent(cref, eref);
		} else {	/*  channel events */
			int overlap = 0;
			if (MDGetKind(eref) == kMDEventNote) {
				/*  Register the note-off for later output  */
				MDEvent noteOffEvent, *ep;
				MDEventInit(&noteOffEvent);
				MDSetKind(&noteOffEvent, kMDEventInternalNoteOff);
				MDSetCode(&noteOffEvent, MDGetCode(eref));
				MDSetChannel(&noteOffEvent, MDGetChannel(eref));
				MDSetNoteOffVelocity(&noteOffEvent, MDGetNoteOffVelocity(eref));
				MDSetTick(&noteOffEvent, MDGetTick(eref) + MDGetDuration(eref));
			#if 1
				/*  Search from the end of registered note-off  */
				MDPointerSetPosition(noteOffPtr, MDTrackGetNumberOfEvents(noteOffTrack));
				while ((ep = MDPointerBackward(noteOffPtr)) != NULL && MDGetTick(ep) > MDGetTick(&noteOffEvent)) {
					if (MDGetCode(ep) == MDGetCode(eref) && MDGetChannel(ep) == MDGetChannel(eref))
						/*  Two note events are overlapping and first-in is NOT first-out  */
						overlap = 1;
				}
			#else
			/*	MDPointerSetPosition(noteOffPtr, 0);
				MDPointerJumpToTick(noteOffPtr, MDGetTick(&noteOffEvent) + 1); */
			#endif
				result = MDPointerInsertAnEvent(noteOffPtr, &noteOffEvent);
				if (result != kMDNoError)
					break;
				if (noteOffTick > MDGetTick(&noteOffEvent))
					noteOffTick = MDGetTick(&noteOffEvent);
                dprintf(2, "a note-off registered, tick %ld code %d vel %d\n", MDGetTick(&noteOffEvent), MDGetCode(&noteOffEvent), MDGetNoteOffVelocity(&noteOffEvent));
                dprintf(2, "num of pending note-offs = %ld\n", MDTrackGetNumberOfEvents(noteOffTrack));
			}
			if (overlap) {
				/*  Write a special 'duration' meta-event  */
				result = MDSequenceWriteSMFSpecialDurationEvent(cref, eref);
				if (result != kMDNoError)
					break;
				/*  Write deltatime 0  */
				if (PUTC(0, cref->stream) == EOF) {
					result = kMDErrorCannotWriteToStream;
					break;
				}
			}
			result = MDSequenceWriteSMFChannelEvent(cref, eref);
		}
		
		if (result != kMDNoError)
			break;
	} /* end while  */
	
	/*  Write the remaining note-off events  */
	if (result == kMDNoError && noteOffTick < kMDMaxTick) {
		MDPointerSetPosition(noteOffPtr, -1);
		while ((noteOffRef = MDPointerForward(noteOffPtr)) != NULL) {
				dprintf(2, "a pending note-off output, tick %ld code %d vel %d\n", MDGetTick(noteOffRef), MDGetCode(noteOffRef), MDGetNoteOffVelocity(noteOffRef));
			result = MDSequenceWriteSMFDeltaTime(cref, MDGetTick(noteOffRef));
			if (result == kMDNoError)
				result = MDSequenceWriteSMFChannelEvent(cref, noteOffRef);
			if (result != kMDNoError)
				break;
		}
	}

	/*  Write the end-of-track event  */
	if (result == kMDNoError) {
		if (eotSelected || pset == NULL || pset == (IntGroup *)(-1))
			cref->deltatime = MDTrackGetDuration(cref->temptrk) - cref->tick;
		else
			cref->deltatime = 1;
		if (MDWriteStreamFormat(cref->stream, "w", cref->deltatime) != 1 || FWRITE_(sEndOfTrack, sizeof sEndOfTrack, cref->stream) < sizeof sEndOfTrack)
			result = kMDErrorCannotWriteToStream;
	}
	
	last:
	MDPointerRelease(ptr);
	MDPointerRelease(noteOffPtr);
	MDTrackRelease(noteOffTrack);
	return result;
}

MDStatus
MDSequenceWriteSMFWithSelection(MDSequence *inSequence, IntGroup **psetArray, char *eotSelectFlags, STREAM stream, MDSequenceCallback callback, void *cbdata)
{
	MDStatus result = kMDNoError;
	MDSMFConvert conv;
	short trkno, trkmax;
	int32_t size, pos;
	
	if (inSequence == NULL || stream == NULL)
		return kMDErrorInternalError;

	/*  Initialize the convert record  */
	memset(&conv, 0, sizeof(conv));
	conv.stream = stream;
	conv.sequence = inSequence;
	conv.timebase = MDSequenceGetTimebase(inSequence);
	trkmax = MDSequenceGetNumberOfTracks(inSequence);
	if (psetArray != NULL) {
		conv.trkno = 0;
		for (trkno = 0; trkno < trkmax; trkno++) {
			if (psetArray[trkno] != NULL)
				conv.trkno++;
		}
	} else {
		conv.trkno = trkmax;
	}
	conv.callback = callback;
	conv.cbdata = cbdata;
	conv.track_index = 0;
    
/*	if (conv.trkno < 1)
		return kMDErrorInternalError; */

	/*  Write the file header */
	if (MDWriteStreamFormat(conv.stream, "A4Nn3", "MThd", 6L,
		(short)(conv.trkno == 1 ? 0 : 1), (short)conv.trkno, (short)conv.timebase) != 5)
			result = kMDErrorCannotWriteToStream;
	
	/*  Write each track  */
	for (trkno = 0; trkno < trkmax; trkno++) {
		IntGroup *pset;
		char eotSelected;
		if (psetArray != NULL) {
			pset = psetArray[trkno];
			if (pset == NULL) {
			/*	if (trkno == 0)
					pset = (IntGroup *)(-1);	*//*  An empty selection; conductor track will always be written */
			/*	else */
					continue;
			}
		} else pset = NULL;

		if (eotSelectFlags != NULL)
			eotSelected = eotSelectFlags[trkno];
		else eotSelected = 0;

		/*  Get the track  */
		conv.temptrk = MDSequenceGetTrack(inSequence, trkno);
		if (conv.temptrk == NULL) {
			result = kMDErrorInternalError;
			break;
		}
	/*	conv.track_index = trkno; */
        if (MDSequenceIsSingleChannelMode(inSequence))
            conv.track_channel = MDTrackGetTrackChannel(conv.temptrk) & 15;
        else
            conv.track_channel = 16;
		if (MDWriteStreamFormat(conv.stream, "A4N", "MTrk", 0L) == 2) {
			conv.pos = (int32_t)FTELL(conv.stream) - 4;
		/*	if (pset == (IntGroup *)(-1))
				result = kMDNoError;
			else */
			result = MDSequenceWriteSMFTrackWithSelection(&conv, pset, eotSelected);
			if (result != kMDNoError) {
				dprintf(0, "Error %d occurred during write of SMF track\n", result);
			}
			pos = (int32_t)FTELL(conv.stream);
			size = pos - conv.pos - 4;
			FSEEK(conv.stream, conv.pos, SEEK_SET);
			MDWriteStreamFormat(conv.stream, "N", size);
			FSEEK(conv.stream, pos, SEEK_SET);
			if (result != kMDNoError)
				break;
		} else {
			result = kMDErrorCannotWriteToStream;
			break;
		}
		conv.track_index++;
	}
	
	return result;
}

MDStatus
MDSequenceWriteSMF(MDSequence *inSequence, STREAM stream, MDSequenceCallback callback, void *cbdata)
{
	return MDSequenceWriteSMFWithSelection(inSequence, NULL, NULL, stream, callback, cbdata);
}

#pragma mark ====== Read/Write Catalog ======

MDStatus
MDSequenceWriteCatalog(MDCatalog *inCatalog, STREAM stream)
{
	char buf[64];
	int i;
	off_t pos0, pos1;
	pos0 = FTELL(stream);
	MDWriteStreamFormat(stream, "N", (int32_t)0);  /*  Dummy  */
	MDWriteStreamFormat(stream, "N", (int32_t)inCatalog->num);
	MDWriteStreamFormat(stream, "NN", (int32_t)inCatalog->startTick, (int32_t)inCatalog->endTick);
	pos1 = FTELL(stream);
	FSEEK(stream, pos0, SEEK_SET);
	MDWriteStreamFormat(stream, "N", (int32_t)(pos1 - pos0 - 4));
	FSEEK(stream, pos1, SEEK_SET);

	for (i = 0; i < inCatalog->num; i++) {
		MDCatalogTrack *cat = inCatalog->catTrack + i;
		pos0 = FTELL(stream);
		MDWriteStreamFormat(stream, "N", (int32_t)0);  /*  Dummy  */
		memset(buf, 0, 64);
		strncpy(buf, cat->name, 63);
		MDWriteStreamFormat(stream, "NA64NN", (int32_t)cat->originalTrackNo, buf, (int32_t)cat->numEvents, (int32_t)cat->numMIDIEvents);
		pos1 = FTELL(stream);
		FSEEK(stream, pos0, SEEK_SET);
		MDWriteStreamFormat(stream, "N", (int32_t)(pos1 - pos0 - 4));
		FSEEK(stream, pos1, SEEK_SET);
	}
	return kMDNoError;
}

MDCatalog *
MDSequenceReadCatalog(STREAM stream)
{
	int i;
	int32_t num, num2, num3;
	off_t pos0;
	MDCatalog *catalog;

	pos0 = FTELL(stream);
	if (MDReadStreamFormat(stream, "N", &num) < 1)
		return NULL;
	pos0 += num - 4;
	MDReadStreamFormat(stream, "NNN", &num, &num2, &num3);
	catalog = (MDCatalog *)malloc(sizeof(MDCatalog) + (num - 1) * sizeof(MDCatalogTrack));
	if (catalog == NULL)
		return NULL;
	memset(catalog, 0, sizeof(MDCatalog) + (num - 1) * sizeof(MDCatalogTrack));
	catalog->num = num;
	catalog->startTick = num2;
	catalog->endTick = num3;
	FSEEK(stream, pos0, SEEK_SET);
	for (i = 0; i < catalog->num; i++) {
		MDCatalogTrack *cat = catalog->catTrack + i;
		MDReadStreamFormat(stream, "N", &num);
		pos0 += num - 4;
		MDReadStreamFormat(stream, "NA64NN", &num, cat->name, &num2, &num3);
		cat->name[63] = 0;
		cat->originalTrackNo = num;
		cat->numEvents = num2;
		cat->numMIDIEvents = num3;
		FSEEK(stream, pos0, SEEK_SET);
	}
	return catalog;
}
