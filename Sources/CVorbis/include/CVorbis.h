// Schmale C-Schnittstelle zum Ogg-Vorbis-Decoder stb_vorbis (v1.22, MIT/Public Domain, Sean Barrett).
#ifndef CVORBIS_H
#define CVORBIS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cvorbis_decoder cvorbis_decoder;

/// Öffnet eine Ogg-Vorbis-Datei (UTF-8-Pfad). Bei Fehlern NULL und `*error` > 0.
cvorbis_decoder *cvorbis_open(const char *path, int *error);
int cvorbis_channels(const cvorbis_decoder *d);
int cvorbis_sample_rate(const cvorbis_decoder *d);
/// Gesamtlänge in Frames (Samples je Kanal); 0, wenn unbekannt.
unsigned long long cvorbis_total_frames(cvorbis_decoder *d);
/// Liest bis zu `max_frames` Frames verschachtelt (L R L R …) als Float; Rückgabe: gelesene Frames, 0 = Ende.
int cvorbis_read_interleaved(cvorbis_decoder *d, float *buffer, int max_frames);
/// Springt zu einem Frame; 1 = Erfolg.
int cvorbis_seek(cvorbis_decoder *d, unsigned long long frame);
void cvorbis_close(cvorbis_decoder *d);

#ifdef __cplusplus
}
#endif
#endif
