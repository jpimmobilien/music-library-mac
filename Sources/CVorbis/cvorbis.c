// Bindet stb_vorbis (unverändert, siehe vendor/) ein und stellt die Funktionen aus CVorbis.h bereit.
#define STB_VORBIS_NO_PUSHDATA_API
#include "vendor/stb_vorbis.c"
#include "CVorbis.h"

struct cvorbis_decoder {
    stb_vorbis *v;
    int channels;
    int sample_rate;
};

cvorbis_decoder *cvorbis_open(const char *path, int *error) {
    int err = 0;
    stb_vorbis *v = stb_vorbis_open_filename(path, &err, NULL);
    if (!v) {
        if (error) *error = err ? err : -1;
        return NULL;
    }
    stb_vorbis_info info = stb_vorbis_get_info(v);
    if (info.channels <= 0 || info.sample_rate == 0) {
        stb_vorbis_close(v);
        if (error) *error = -2;
        return NULL;
    }
    cvorbis_decoder *d = (cvorbis_decoder *)malloc(sizeof(cvorbis_decoder));
    if (!d) {
        stb_vorbis_close(v);
        if (error) *error = -3;
        return NULL;
    }
    d->v = v;
    d->channels = info.channels;
    d->sample_rate = (int)info.sample_rate;
    if (error) *error = 0;
    return d;
}

int cvorbis_channels(const cvorbis_decoder *d) { return d ? d->channels : 0; }

int cvorbis_sample_rate(const cvorbis_decoder *d) { return d ? d->sample_rate : 0; }

unsigned long long cvorbis_total_frames(cvorbis_decoder *d) {
    if (!d) return 0;
    return (unsigned long long)stb_vorbis_stream_length_in_samples(d->v);
}

int cvorbis_read_interleaved(cvorbis_decoder *d, float *buffer, int max_frames) {
    if (!d || !buffer || max_frames <= 0) return 0;
    return stb_vorbis_get_samples_float_interleaved(d->v, d->channels, buffer, max_frames * d->channels);
}

int cvorbis_seek(cvorbis_decoder *d, unsigned long long frame) {
    if (!d) return 0;
    return stb_vorbis_seek(d->v, (unsigned int)frame);
}

void cvorbis_close(cvorbis_decoder *d) {
    if (!d) return;
    stb_vorbis_close(d->v);
    free(d);
}
