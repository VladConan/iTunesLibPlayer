
#import <math.h>
#define M_PIf 3.14159265358979323846264338327f
#define M_LN2f      0.693147180559945309417f

#define db2lin(x) ((x) > -90.0f ? powf(10.0f, (x) * 0.05f) : 0.0f)


#define LN_2_2 0.34657359f
#define FLUSH_TO_ZERO(x) (((*(unsigned int*)&(x))&0x7f800000)==0)?0.0f:(x)
#define NEGF(x)(((*(unsigned int*)&(x))^0x80000000))
#define LIMIT(v,l,u) ((v)<(l)?(l):((v)>(u)?(u):(v)))
#define BWIDTH        1.0f
#define BWIDTH_BP     .1f
#define BAND_NO 8
extern const float eqf[BAND_NO];
typedef struct {
	float a1,
	a2,
	b0,
	b1,
	b2,
	x1,
	x2,
	y1,
	y2;
} biquad;

static inline void biquad_init(biquad *f)
{
	
	f->x1 = 0.0f;
	f->x2 = 0.0f;
	f->y1 = 0.0f;
	f->y2 = 0.0f;
}
static inline
void
eq_set_params(biquad *f, float fc, float gain, float bw, float fs) {
	
	float w = 2.0f * M_PIf * LIMIT(fc, 1.0f, fs*.5f) / fs;
	float cw = cosf(w);
	float sw = sinf(w);
	float J = powf(10.0f, gain * 0.025f);
	float g = sw * sinhf(LN_2_2 * LIMIT(bw, 0.0001f, 4.0f) * w / sw);
	float a0r = 1.0f / (1.0f + (g / J));
	
	f->b0 = (1.0f + (g * J)) * a0r;
	f->b1 = (-2.0f * cw) * a0r;
	f->b2 = (1.0f - (g * J)) * a0r;
	f->a1 = -(f->b1);
	f->a2 = ((g / J) - 1.0f) * a0r;
}


static inline void lp_set_params(biquad *f, float fc, float bw, float fs) {
	float omega = 2.0f * M_PIf * fc/fs;
	float sn = sin(omega);
	float cs = cos(omega);
	float alpha = sn * sinh(M_LN2f / 2.0f * bw * omega / sn);
	
	const float a0r = 1.0f / (1.0f + alpha);
#if 0
	b0 = (1 - cs) /2;
	b1 = 1 - cs;
	b2 = (1 - cs) /2;
	a0 = 1 + alpha;
	a1 = -2 * cs;
	a2 = 1 - alpha;
#endif
	f->b0 = a0r * (1.0f - cs) * 0.5f;
	f->b1 = a0r * (1.0f - cs);
	f->b2 = a0r * (1.0f - cs) * 0.5f;
	f->a1 = a0r * (2.0f * cs);
	f->a2 = a0r * (alpha - 1.0f);
}


static inline
void
hp_set_params(biquad *f, float fc, float bw, float fs)
{
	float omega = 2.0f * M_PIf * fc/fs;
	float sn = sin(omega);
	float cs = cos(omega);
	float alpha = sn * sinh(M_LN2f / 2.0f * bw * omega / sn);
	
	const float a0r = 1.0f / (1.0f + alpha);
	
#if 0
	b0 = (1 + cs) /2;
	b1 = -(1 + cs);
	b2 = (1 + cs) /2;
	a0 = 1 + alpha;
	a1 = -2 * cs;
	a2 = 1 - alpha;
#endif
	f->b0 = a0r * (1.0f + cs) * 0.5f;
	f->b1 = a0r * -(1.0f + cs);
	f->b2 = a0r * (1.0f + cs) * 0.5f;
	f->a1 = a0r * (2.0f * cs);
	f->a2 = a0r * (alpha - 1.0f);
}


static inline
void
ls_set_params(biquad *f, float fc, float gain, float slope, float fs)
{
	
	float w = 2.0f * M_PIf * LIMIT(fc, 1.0f, fs/2.0f) / fs;
	float cw = cos(w);
	float sw = sin(w);
	float A = pow(10.0f, gain * 0.025f);
	float b = sqrt(((1.0f + A * A) / LIMIT(slope, 0.0001f, 1.0f)) - ((A -
																	  1.0f) * (A - 1.0f)));
	float apc = cw * (A + 1.0f);
	float amc = cw * (A - 1.0f);
	float bs = b * sw;
	float a0r = 1.0f / (A + 1.0f + amc + bs);
	
	f->b0 = a0r * A * (A + 1.0f - amc + bs);
	f->b1 = a0r * 2.0f * A * (A - 1.0f - apc);
	f->b2 = a0r * A * (A + 1.0f - amc - bs);
	f->a1 = a0r * 2.0f * (A - 1.0f + apc);
	f->a2 = a0r * (-A - 1.0f - amc + bs);
}


static inline
void
hs_set_params(biquad *f, float fc, float gain, float slope, float fs) {
	
	float w = 2.0f * M_PIf * LIMIT(fc, 1.0f, fs/2.0f) / fs;
	float cw = cos(w);
	float sw = sin(w);
	float A = pow(10.0f, gain * 0.025f);
	float b = sqrt(((1.0f + A * A) / LIMIT(slope, 0.0001f, 1.0f)) - ((A -
																	  1.0f) * (A - 1.0f)));
	float apc = cw * (A + 1.0f);
	float amc = cw * (A - 1.0f);
	float bs = b * sw;
	float a0r = 1.0f / (A + 1.0f - amc + bs);
	
	f->b0 = a0r * A * (A + 1.0f + amc + bs);
	f->b1 = a0r * -2.0f * A * (A - 1.0f + apc);
	f->b2 = a0r * A * (A + 1.0f + amc - bs);
	f->a1 = a0r * -2.0f * (A - 1.0f - apc);
	f->a2 = a0r * (-A - 1.0f + amc + bs);
}


static inline
float
biquad_run(biquad *f, float x) {
	
	float y;
	
	y = (f->b0 * x) + (f->b1 * f->x1) + (f->b2 * f->x2)
	+ (f->a1 * f->y1) + (f->a2 * f->y2);
	f->x2 = f->x1;
	f->x1 = x;
	f->y2 = f->y1;
	f->y1 = y;
	
	return y;
}
static inline
float push_buffer(float insample, float * buffer,
				  unsigned long buflen, unsigned long* pos) {
	
	float outsample;
	
	outsample = buffer[*pos];
	buffer[*pos++] = insample;
	
	if (*pos >= buflen)
		pos = 0;
	
	return outsample;
}
/* read a value from a ringbuffer.
 * n == 0 returns the oldest sample from the buffer.
 * n == buflen-1 returns the sample written to the buffer
 *      at the last push_buffer call.
 * n must not exceed buflen-1, or your computer will explode.
 */
static inline
float read_buffer(float * buffer, unsigned long buflen,
				  unsigned long pos, unsigned long n)
{
	
	while (n + pos >= buflen)
		n -= buflen;
	return buffer[n + pos];
}



    typedef struct
    {
        biquad filters[BAND_NO];
        float gains[BAND_NO];
        float chg[BAND_NO];
        float sr;
    } Eq8;

static inline
void SetEq(Eq8* this)
{
    eq_set_params(&(this->filters[0]), eqf[0], this->chg[0], BWIDTH, this->sr);
    eq_set_params(&(this->filters[1]), eqf[1], this->chg[1], BWIDTH, this->sr);
    eq_set_params(&(this->filters[2]), eqf[2], this->chg[2], BWIDTH, this->sr);
    eq_set_params(&(this->filters[3]), eqf[3], this->chg[3], BWIDTH, this->sr);
    eq_set_params(&(this->filters[4]), eqf[4], this->chg[4], BWIDTH, this->sr);
    eq_set_params(&(this->filters[5]), eqf[5], this->chg[5], BWIDTH, this->sr);
    eq_set_params(&(this->filters[6]), eqf[6], this->chg[6], BWIDTH, this->sr);
    eq_set_params(&(this->filters[7]), eqf[7], this->chg[7], BWIDTH, this->sr);

}
static inline
void initEq8(Eq8* this,float samplerate)
{
    this->sr = samplerate;
    for (int i=0; i <BAND_NO;i++)
    {
        this->chg[i]=0.f;
        this->filters[i].x1=this->filters[i].x2=this->filters[i].y1=this->filters[i].y2=0;
    }
    SetEq(this);
}
static inline
void SetGainEq8(Eq8* this, int band,float gain)
{
    this->chg[band]=gain;
    eq_set_params(&(this->filters[band]), eqf[band], gain, BWIDTH, this->sr);
}
static inline
void runEq8(Eq8* this, float *output,float *input, unsigned long sample_count)
{
    float samp;
    for ( unsigned long pos = 0; pos < sample_count; pos++) {
        samp = input[pos];
        if (this->chg[0] != 0.0f)
            samp = biquad_run(&this->filters[0], samp);
        if (this->chg[1] != 0.0f)
            samp = biquad_run(&this->filters[1], samp);
        if (this->chg[2] != 0.0f)
            samp = biquad_run(&this->filters[2], samp);
        if (this->chg[3] != 0.0f)
            samp = biquad_run(&this->filters[3], samp);
        if (this->chg[4] != 0.0f)
            samp = biquad_run(&this->filters[4], samp);
        if (this->chg[5] != 0.0f)
            samp = biquad_run(&this->filters[5], samp);
        if (this->chg[6] != 0.0f)
            samp = biquad_run(&this->filters[6], samp);
        if (this->chg[7] != 0.0f)
            samp = biquad_run(&this->filters[7], samp);


        output[pos] = samp;
    }
    
}
static inline
float tickEq8(Eq8* this, float input)
{
    float samp;
        samp = input;
        if (this->chg[0] != 0.0f)
            samp = biquad_run(&this->filters[0], samp);
        if (this->chg[1] != 0.0f)
            samp = biquad_run(&this->filters[1], samp);
        if (this->chg[2] != 0.0f)
            samp = biquad_run(&this->filters[2], samp);
        if (this->chg[3] != 0.0f)
            samp = biquad_run(&this->filters[3], samp);
        if (this->chg[4] != 0.0f)
            samp = biquad_run(&this->filters[4], samp);
        if (this->chg[5] != 0.0f)
            samp = biquad_run(&this->filters[5], samp);
        if (this->chg[6] != 0.0f)
            samp = biquad_run(&this->filters[6], samp);
        if (this->chg[7] != 0.0f)
            samp = biquad_run(&this->filters[7], samp);
        
    return samp;
}