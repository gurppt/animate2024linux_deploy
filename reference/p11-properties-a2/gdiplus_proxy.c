/* Proxy gdiplus Animate 2024 / Wine.
 * FIX (GdipDrawString) : transform monde NaN -> ValueOverflow ; reset+redraw+Ok.
 * TRACE : logge la 1ere apparition du NaN a la SOURCE (setters transform, builders
 * matrice) + hauteur de police renvoyee par le vrai gdiplus (suspect: gdi32 Wine -> 0).
 * 629 autres exports forwardes (.def). ZERO octet Adobe modifie. */
#include <windows.h>
#include <stdio.h>

typedef int GpStatus; typedef struct { float X,Y,W,H; } RectF;
typedef void GpGraphics; typedef void GpFont; typedef void GpFontFamily; typedef void GpMatrix;
#define PF(n,...) typedef GpStatus (__stdcall *n)(__VA_ARGS__)
PF(fn_DrawString,GpGraphics*,const WCHAR*,int,const GpFont*,const RectF*,const void*,const void*);
PF(fn_GetFamily,const GpFont*,GpFontFamily**);
PF(fn_GetFamilyName,const GpFontFamily*,WCHAR*,unsigned short);
PF(fn_CreateMatrix,GpMatrix**);
PF(fn_GetWorldTransform,GpGraphics*,GpMatrix*);
PF(fn_SetWorldTransform,GpGraphics*,GpMatrix*);
PF(fn_ResetWorldTransform,GpGraphics*);
PF(fn_GetMatrixElements,const GpMatrix*,float*);
PF(fn_DeleteMatrix,GpMatrix*);
PF(fn_TranslateWorldTransform,GpGraphics*,float,float,int);
PF(fn_MultiplyWorldTransform,GpGraphics*,GpMatrix*,int);
PF(fn_SetMatrixElements,GpMatrix*,float,float,float,float,float,float);
PF(fn_TranslateMatrix,GpMatrix*,float,float,int);
PF(fn_GetFontHeight,const GpFont*,const GpGraphics*,float*);
PF(fn_GetFontHeightGivenDPI,const GpFont*,float,float*);
/* metriques de famille : suspect = EmHeight 0 -> division dvaui -> dy NaN */
PF(fn_GetEmHeight,const GpFontFamily*,int,unsigned short*);
PF(fn_GetCellAscent,const GpFontFamily*,int,unsigned short*);
PF(fn_GetCellDescent,const GpFontFamily*,int,unsigned short*);
PF(fn_GetLineSpacing,const GpFontFamily*,int,unsigned short*);
PF(fn_MeasureString,GpGraphics*,const WCHAR*,int,const GpFont*,const RectF*,const void*,RectF*,int*,int*);
PF(fn_CreateFont,const GpFontFamily*,float,int,int,GpFont**);
PF(fn_GetFontSize,const GpFont*,float*);
PF(fn_GetStringFormatAlign,const void*,int*);
PF(fn_GetStringFormatLineAlign,const void*,int*);
PF(fn_GetStringFormatFlags,const void*,int*);
PF(fn_CreateSolidFill,unsigned int,void**);
PF(fn_FillRectangle,GpGraphics*,const void*,float,float,float,float);
PF(fn_DeleteBrush,void*);
PF(fn_SaveGraphics,GpGraphics*,unsigned int*);
PF(fn_RestoreGraphics,GpGraphics*,unsigned int);
typedef struct { float X,Y; } PtF;
PF(fn_DrawDriverString,GpGraphics*,const unsigned short*,int,const GpFont*,const void*,const PtF*,int,const GpMatrix*);

static HMODULE real;
static fn_DrawString p_DrawString; static fn_GetFamily p_GetFamily; static fn_GetFamilyName p_GetFamilyName;
static fn_CreateMatrix p_CreateMatrix; static fn_GetWorldTransform p_GetWorldTransform;
static fn_SetWorldTransform p_SetWorldTransform; static fn_ResetWorldTransform p_ResetWorldTransform;
static fn_GetMatrixElements p_GetMatrixElements; static fn_DeleteMatrix p_DeleteMatrix;
static fn_TranslateWorldTransform p_TranslateWorldTransform; static fn_MultiplyWorldTransform p_MultiplyWorldTransform;
static fn_SetMatrixElements p_SetMatrixElements; static fn_TranslateMatrix p_TranslateMatrix;
static fn_GetFontHeight p_GetFontHeight; static fn_GetFontHeightGivenDPI p_GetFontHeightGivenDPI;
static fn_GetEmHeight p_GetEmHeight; static fn_GetCellAscent p_GetCellAscent;
static fn_GetCellDescent p_GetCellDescent; static fn_GetLineSpacing p_GetLineSpacing;
static fn_MeasureString p_MeasureString;
static fn_CreateFont p_CreateFont; static fn_GetFontSize p_GetFontSize;
static fn_GetStringFormatAlign p_GetStringFormatAlign;
static fn_GetStringFormatLineAlign p_GetStringFormatLineAlign;
static fn_GetStringFormatFlags p_GetStringFormatFlags;
static fn_CreateSolidFill p_CreateSolidFill;
static fn_FillRectangle p_FillRectangle;
static fn_DeleteBrush p_DeleteBrush;
static fn_SaveGraphics p_SaveGraphics;
static fn_RestoreGraphics p_RestoreGraphics;
static fn_DrawDriverString p_DrawDriverString;
static LONG g_fixed, g_failopen;

static void ensure(void){
    static volatile LONG st=0; LONG prev=InterlockedCompareExchange(&st,1,0);
    if(prev==2) return; if(prev==1){ while(st!=2) Sleep(0); return; }
    real=LoadLibraryW(L"gdiplus_real.dll"); if(!real) real=LoadLibraryW(L"C:\\windows\\system32\\gdiplus_real.dll");
    #define G(x,f) p_##x=(fn_##x)GetProcAddress(real,"Gdip" f)
    G(DrawString,"DrawString"); G(GetFamily,"GetFamily"); G(GetFamilyName,"GetFamilyName");
    G(CreateMatrix,"CreateMatrix"); G(GetWorldTransform,"GetWorldTransform"); G(SetWorldTransform,"SetWorldTransform");
    G(ResetWorldTransform,"ResetWorldTransform"); G(GetMatrixElements,"GetMatrixElements"); G(DeleteMatrix,"DeleteMatrix");
    G(TranslateWorldTransform,"TranslateWorldTransform"); G(MultiplyWorldTransform,"MultiplyWorldTransform");
    G(SetMatrixElements,"SetMatrixElements"); G(TranslateMatrix,"TranslateMatrix");
    G(GetFontHeight,"GetFontHeight"); G(GetFontHeightGivenDPI,"GetFontHeightGivenDPI");
    G(GetEmHeight,"GetEmHeight"); G(GetCellAscent,"GetCellAscent");
    G(GetCellDescent,"GetCellDescent"); G(GetLineSpacing,"GetLineSpacing");
    G(MeasureString,"MeasureString");
    G(CreateFont,"CreateFont"); G(GetFontSize,"GetFontSize");
    G(GetStringFormatAlign,"GetStringFormatAlign");
    G(GetStringFormatLineAlign,"GetStringFormatLineAlign");
    G(GetStringFormatFlags,"GetStringFormatFlags");
    G(CreateSolidFill,"CreateSolidFill");
    G(FillRectangle,"FillRectangle");
    G(DeleteBrush,"DeleteBrush");
    G(SaveGraphics,"SaveGraphics");
    G(RestoreGraphics,"RestoreGraphics");
    G(DrawDriverString,"DrawDriverString");
    InterlockedExchange(&st,2);
}
static int badf(float v){ return (v!=v)||(v>1e18f)||(v<-1e18f); }
static void trace(const char* fmt,...){ FILE* f=fopen("C:\\gdiplus_trace.log","a"); if(!f) return;
    va_list a; va_start(a,fmt); vfprintf(f,fmt,a); va_end(a); fclose(f); }
static LONG c_swt,c_twt,c_mwt,c_sme,c_tm,c_fh,c_met,c_ms; /* compteurs pour capper le log */
static DWORD g_tlsNan = TLS_OUT_OF_INDEXES; /* flag par thread: translate NaN vient d'etre neutralise */

/* nom ascii de la famille (pour log) */
static void famname(const GpFontFamily* fam, char* out, int cap){
    WCHAR w[32]={0}; out[0]=0;
    if(fam && p_GetFamilyName && p_GetFamilyName(fam,w,0)==0){
        int i; for(i=0;i<cap-1 && w[i];i++) out[i]=(w[i]<128)?(char)w[i]:'?';
        out[i]=0;
    }
}
/* metrique de famille: trace + FIX A LA SOURCE (Fable, fable_nan_source_analysis.md).
 * dvaui+0x27F198 : dy = penY - (CellAscent*fontSize)/EmHeight. Pour les polices
 * privees Adobe (OTF/CFF) rejetees par ce gdiplus, les metriques renvoient
 * status!=0 avec valeur 0 -> 0/0 = NaN -> dy NaN + layout des chiffres NaN
 * (champs "     ."). FIX : substituer QUEL QUE SOIT le status et renvoyer Ok. */
static LONG c_metfix;
static GpStatus metric_common(const char* fn, unsigned short subst,
                              GpStatus s, const GpFontFamily* fam, int style, unsigned short* v){
    char nm[32];
    if(v && InterlockedIncrement(&c_met)<=48){
        famname(fam,nm,sizeof(nm));
        trace("%s(fam=%s,style=%d) => %u (status=%d)\n",fn,nm,style,(unsigned)*v,s);
    }
    if(v && (s!=0 || *v==0)){
        if(InterlockedIncrement(&c_metfix)<=40){
            famname(fam,nm,sizeof(nm));
            trace("%s FIX: status=%d val=%u fam=%s -> %u, Ok\n",fn,s,(unsigned)*v,nm,(unsigned)subst);
        }
        *v=subst; s=0;
    }
    return s;
}
__declspec(dllexport) GpStatus __stdcall GdipGetEmHeight(const GpFontFamily* f,int st,unsigned short* v){
    ensure(); return metric_common("GetEmHeight",2048,p_GetEmHeight(f,st,v),f,st,v);
}
__declspec(dllexport) GpStatus __stdcall GdipGetCellAscent(const GpFontFamily* f,int st,unsigned short* v){
    ensure(); return metric_common("GetCellAscent",1854,p_GetCellAscent(f,st,v),f,st,v);
}
__declspec(dllexport) GpStatus __stdcall GdipGetCellDescent(const GpFontFamily* f,int st,unsigned short* v){
    ensure(); return metric_common("GetCellDescent",434,p_GetCellDescent(f,st,v),f,st,v);
}
__declspec(dllexport) GpStatus __stdcall GdipGetLineSpacing(const GpFontFamily* f,int st,unsigned short* v){
    ensure(); return metric_common("GetLineSpacing",2355,p_GetLineSpacing(f,st,v),f,st,v);
}
/* CreateFont: le validateur GDI+ (emSize<=0) LAISSE PASSER NaN (comparaison NaN=false).
 * Une police de taille NaN rend tout invisible + propage dy=NaN. Trace + FIX. */
static LONG c_cf;
__declspec(dllexport) GpStatus __stdcall GdipCreateFont(const GpFontFamily* fam,float emSize,int style,int unit,GpFont** font){
    ensure();
    if(badf(emSize)||emSize<=0.0f){
        char nm[32]; famname(fam,nm,sizeof(nm));
        trace("CreateFont NaN/invalide: fam=%s size=%g unit=%d -> substitue 11\n",nm,emSize,unit);
        emSize=11.0f;
    }
    return p_CreateFont(fam,emSize,style,unit,font);
}
/* GetFontSize: complement du fix metriques — une taille NaN/<=0 propagerait le NaN. */
static LONG c_gfs;
__declspec(dllexport) GpStatus __stdcall GdipGetFontSize(const GpFont* font,float* size){
    ensure(); GpStatus s=p_GetFontSize?p_GetFontSize(font,size):18;
    if(font && size && (s!=0 || badf(*size) || *size<=0.0f)){
        if(InterlockedIncrement(&c_gfs)<=20) trace("GetFontSize FIX: status=%d size=%g -> 11, Ok\n",s,*size);
        *size=11.0f; s=0;
    }
    return s;
}
/* DrawDriverString: chemin des NOMBRES dynamiques (glyphes positionnes un a un).
 * Si les positions contiennent le NaN de la chaine dvaui -> GDI+ rejette -> nombres absents.
 * Diagnostic + sanitize : NaN remplace par la derniere coordonnee finie vue. */
static LONG c_dds;
static LONG c_dds_numeric;
__declspec(dllexport) GpStatus __stdcall GdipDrawDriverString(GpGraphics* g,const unsigned short* txt,int len,const GpFont* font,const void* brush,const PtF* pos,int flags,const GpMatrix* matrix){
    ensure();
    int npos = (flags&4)?1:(len>0?len:0); /* RealizedAdvance=4 -> 1 seule position */
    int i, nbad=0;
    for(i=0;i<npos;i++) if(badf(pos[i].X)||badf(pos[i].Y)) nbad++;
    float e[6]={0}; int badm=0;
    if(matrix && p_GetMatrixElements && p_GetMatrixElements((GpMatrix*)matrix,e)==0)
        for(i=0;i<6;i++) if(badf(e[i])) badm=1;
    float fs=-1.0f; if(p_GetFontSize) p_GetFontSize(font,&fs);
    if(txt&&len>0&&len<=16&&GetEnvironmentVariableA("ANIMATE_GDIPLUS_NUMERIC_TRACE",NULL,0)){
        int alldigits=1,j; char hex[128]="",*hp=hex;
        for(j=0;j<len;j++){
            if(txt[j]<L'0'||txt[j]>L'9')alldigits=0;
            if(hp<hex+120)hp+=sprintf(hp,"%04x ",(unsigned)txt[j]);
        }
        if(alldigits&&InterlockedIncrement(&c_dds_numeric)<=600)
            trace("DRIVER_NUMERIC: len=%d flags=%d fs=%g npos=%d p0=[%g %g] matrix=[%g %g %g %g %g %g] hex=[%s]\n",
                  len,flags,fs,npos,npos>0?pos[0].X:0,npos>0?pos[0].Y:0,
                  e[0],e[1],e[2],e[3],e[4],e[5],hex);
    }
    GpStatus s;
    if(nbad && npos>0){
        /* copie sanitisee: NaN -> derniere valeur finie (ou 0) ; avance X estimee */
        PtF fix[256]; int n=(npos<256)?npos:256;
        float lx=0.0f, ly=0.0f; int havex=0, havey=0;
        for(i=0;i<n;i++){
            fix[i]=pos[i];
            if(badf(fix[i].X)) fix[i].X = havex ? lx + 0.6f*(fs>0?fs:11.0f) : 0.0f;
            if(badf(fix[i].Y)) fix[i].Y = havey ? ly : 0.0f;
            lx=fix[i].X; havex=1; ly=fix[i].Y; havey=1;
        }
        s=p_DrawDriverString(g,txt,len,font,brush,fix,flags,matrix);
        if(InterlockedIncrement(&c_dds)<=40)
            trace("DrawDriverString NaN: len=%d flags=%d fs=%g nbad=%d/%d p0=(%g,%g)->(%g,%g) badm=%d status=%d\n",
                  len,flags,fs,nbad,npos,pos[0].X,pos[0].Y,fix[0].X,fix[0].Y,badm,s);
        return s;
    }
    s=p_DrawDriverString(g,txt,len,font,brush,pos,flags,matrix);
    if(InterlockedIncrement(&c_dds)<=40)
        trace("DrawDriverString: len=%d flags=%d fs=%g p0=(%g,%g) xm=[%g %g %g %g %g %g] badm=%d status=%d\n",
              len,flags,fs,npos>0?pos[0].X:0,npos>0?pos[0].Y:0,e[0],e[1],e[2],e[3],e[4],e[5],badm,s);
    return s;
}
/* MeasureString: si la boite mesuree contient NaN, dvaui centre/positionne en NaN. Trace+sanitize. */
__declspec(dllexport) GpStatus __stdcall GdipMeasureString(GpGraphics* g,const WCHAR* s,int len,const GpFont* f,const RectF* rc,const void* fmt,RectF* bound,int* cp,int* ln){
    ensure(); GpStatus st=p_MeasureString(g,s,len,f,rc,fmt,bound,cp,ln);
    if(bound && (badf(bound->X)||badf(bound->Y)||badf(bound->W)||badf(bound->H))){
        if(InterlockedIncrement(&c_ms)<=20)
            trace("MeasureString NaN bound: [%g %g %g %g] (status=%d) -> 0\n",bound->X,bound->Y,bound->W,bound->H,st);
        if(badf(bound->X)) bound->X=rc?rc->X:0.0f;
        if(badf(bound->Y)) bound->Y=rc?rc->Y:0.0f;
        if(badf(bound->W)) bound->W=0.0f;
        if(badf(bound->H)) bound->H=0.0f;
    }
    return st;
}

/* ---- TRACE : setters de transform / builders de matrice (loggent le 1er NaN) ---- */
__declspec(dllexport) GpStatus __stdcall GdipTranslateWorldTransform(GpGraphics* g,float dx,float dy,int o){
    ensure();
    /* FIX A LA SOURCE : dvaui calcule parfois dy (ou dx) = NaN -> neutralise a 0 pour
     * garder le transform fini. Le texte se positionne alors via la chaine de transform
     * correcte (au decalage fautif pres) au lieu d'etre renvoye a l'origine par le fallback. */
    if(badf(dx)||badf(dy)){
        if(InterlockedIncrement(&c_twt)<=20) trace("TranslateWorldTransform NaN neutralise: dx=%g dy=%g -> 0\n",dx,dy);
        if(badf(dx)) dx=0.0f;
        if(badf(dy)) dy=0.0f;
        TlsSetValue(g_tlsNan,(LPVOID)1); /* marque: le prochain DrawString de CE thread est l'affecte */
    }
    return p_TranslateWorldTransform(g,dx,dy,o);
}
__declspec(dllexport) GpStatus __stdcall GdipSetMatrixElements(GpMatrix* m,float a,float b,float c,float d,float e,float f){
    ensure(); if((badf(a)||badf(b)||badf(c)||badf(d)||badf(e)||badf(f)) && InterlockedIncrement(&c_sme)<=20)
        trace("SetMatrixElements NaN: [%g %g %g %g %g %g]\n",a,b,c,d,e,f);
    return p_SetMatrixElements(m,a,b,c,d,e,f);
}
__declspec(dllexport) GpStatus __stdcall GdipTranslateMatrix(GpMatrix* m,float ox,float oy,int o){
    ensure(); if((badf(ox)||badf(oy)) && InterlockedIncrement(&c_tm)<=20)
        trace("TranslateMatrix NaN: ox=%g oy=%g\n",ox,oy);
    return p_TranslateMatrix(m,ox,oy,o);
}
__declspec(dllexport) GpStatus __stdcall GdipSetWorldTransform(GpGraphics* g,GpMatrix* m){
    ensure(); GpStatus s=p_SetWorldTransform(g,m);
    if(InterlockedIncrement(&c_swt)<=40){ float e[6]={0}; if(p_GetMatrixElements&&p_GetMatrixElements(m,e)==0)
        for(int i=0;i<6;i++) if(badf(e[i])){ trace("SetWorldTransform NaN: [%g %g %g %g %g %g]\n",e[0],e[1],e[2],e[3],e[4],e[5]); break; } }
    return s;
}
__declspec(dllexport) GpStatus __stdcall GdipMultiplyWorldTransform(GpGraphics* g,GpMatrix* m,int o){
    ensure(); if(InterlockedIncrement(&c_mwt)<=40){ float e[6]={0}; if(p_GetMatrixElements&&p_GetMatrixElements(m,e)==0)
        for(int i=0;i<6;i++) if(badf(e[i])){ trace("MultiplyWorldTransform NaN: [%g %g %g %g %g %g]\n",e[0],e[1],e[2],e[3],e[4],e[5]); break; } }
    return p_MultiplyWorldTransform(g,m,o);
}
/* ---- TRACE : hauteur de police renvoyee par le vrai gdiplus (suspect: 0 sous Wine) ---- */
__declspec(dllexport) GpStatus __stdcall GdipGetFontHeight(const GpFont* fo,const GpGraphics* g,float* h){
    ensure(); GpStatus s=p_GetFontHeight(fo,g,h);
    if(h && (badf(*h)||*h==0.0f) && InterlockedIncrement(&c_fh)<=20) trace("GetFontHeight => %g (status=%d)\n",*h,s);
    return s;
}
__declspec(dllexport) GpStatus __stdcall GdipGetFontHeightGivenDPI(const GpFont* fo,float dpi,float* h){
    ensure(); GpStatus s=p_GetFontHeightGivenDPI(fo,dpi,h);
    if(h && (badf(*h)||*h==0.0f) && InterlockedIncrement(&c_fh)<=20) trace("GetFontHeightGivenDPI(dpi=%g) => %g (status=%d)\n",dpi,*h,s);
    return s;
}

/* ---- v9 DIAG: backtrace des DrawString "digitless" (gabarit "H     .") ----
 * Identifie le COMPOSEUR de la chaine sans chiffres (module+offset de chaque frame). */
static LONG c_bt;
static void log_backtrace(const WCHAR* str,int len){
    void* frames[32]; USHORT n,i;
    char line[2048], *p=line;
    n=RtlCaptureStackBackTrace(1,32,frames,NULL);
    p+=sprintf(p,"DIGITLESS draw len=%d [",len);
    for(i=0;i<len&&i<16;i++) p+=sprintf(p,"%04x ",(unsigned)str[i]);
    p+=sprintf(p,"]\n");
    for(i=0;i<n;i++){
        MEMORY_BASIC_INFORMATION mbi;
        char mod[260]="?";
        unsigned long long off=(unsigned long long)frames[i];
        if(VirtualQuery(frames[i],&mbi,sizeof mbi) && mbi.AllocationBase){
            if(GetModuleFileNameA((HMODULE)mbi.AllocationBase,mod,sizeof mod)){
                char* b=mod; char* q; for(q=mod;*q;q++) if(*q=='\\'||*q=='/') b=q+1;
                off=(unsigned long long)frames[i]-(unsigned long long)mbi.AllocationBase;
                p+=sprintf(p,"  #%02u %s+0x%llx\n",i,b,off);
                continue;
            }
        }
        p+=sprintf(p,"  #%02u %p\n",i,(void*)off);
    }
    trace("%s",line);
}
/* ---- FIX : GdipDrawString (transform NaN -> reset+redraw+Ok) ---- */
static LONG c_ds,c_ds2,c_numeric,c_timeline_label,c_timeline_fix;
__declspec(dllexport) GpStatus __stdcall GdipDrawString(GpGraphics* g,const WCHAR* str,int len,const GpFont* font,const RectF* rc,const void* fmt,const void* brush){
    ensure();
    /* P11 diagnostic opt-in: radiographie les vraies valeurs numériques.
     * Le compteur historique c_ds était épuisé avant l'ouverture d'un document,
     * ce qui masquait précisément les champs Timeline. */
    if(str && len!=0 && GetEnvironmentVariableA("ANIMATE_GDIPLUS_NUMERIC_TRACE",NULL,0)){
        int i,nn=len,hasdigit=0;
        if(nn<0){ nn=0; while(str[nn]&&nn<64) nn++; }
        for(i=0;i<nn;i++) if(str[i]>=L'0'&&str[i]<=L'9'){ hasdigit=1; break; }
        if(hasdigit && InterlockedIncrement(&c_numeric)<=600){
            char txt[96]="",*tp=txt; float fs=-1.0f,e[6]={0};
            int n=nn<32?nn:32;
            for(i=0;i<n&&tp<txt+90;i++)
                tp+=sprintf(tp,"%04x ",(unsigned)str[i]);
            if(p_GetFontSize) p_GetFontSize(font,&fs);
            if(p_CreateMatrix&&p_GetWorldTransform&&p_GetMatrixElements){
                GpMatrix* m=NULL;
                if(p_CreateMatrix(&m)==0&&m){
                    if(p_GetWorldTransform(g,m)==0) p_GetMatrixElements(m,e);
                    if(p_DeleteMatrix)p_DeleteMatrix(m);
                }
            }
            trace("NUMERIC draw: len=%d fs=%g rc=[%g %g %g %g] xform=[%g %g %g %g %g %g] hex=[%s]\n",
                  len,fs,rc?rc->X:0,rc?rc->Y:0,rc?rc->W:0,rc?rc->H:0,
                  e[0],e[1],e[2],e[3],e[4],e[5],txt);
        }
    }
    /* P11 Timeline D2: les libelles et les valeurs passent par des DrawString
     * distincts. Capturer aussi "FPS..." et "F..." ainsi que le StringFormat
     * permet de choisir une largeur finie sans supposer le sens de l'alignement. */
    if(str && len!=0 && GetEnvironmentVariableA("ANIMATE_GDIPLUS_NUMERIC_TRACE",NULL,0)){
        int i,nn=len,islabel=0;
        if(nn<0){ nn=0; while(str[nn]&&nn<64) nn++; }
        if(nn>=3 && str[0]==L'F' && str[1]==L'P' && str[2]==L'S') islabel=1;
        else if(nn>=1 && str[0]==L'F'){
            islabel=1;
            for(i=1;i<nn;i++) if(str[i]!=L' ' && str[i]!=L'.'){ islabel=0; break; }
        }
        if(islabel && InterlockedIncrement(&c_timeline_label)<=100){
            char txt[192]="",*tp=txt; float fs=-1.0f,e[6]={0};
            int align=-1,linealign=-1,flags=-1,n=nn<48?nn:48;
            for(i=0;i<n&&tp<txt+186;i++) tp+=sprintf(tp,"%04x ",(unsigned)str[i]);
            if(p_GetFontSize) p_GetFontSize(font,&fs);
            if(fmt && p_GetStringFormatAlign) p_GetStringFormatAlign(fmt,&align);
            if(fmt && p_GetStringFormatLineAlign) p_GetStringFormatLineAlign(fmt,&linealign);
            if(fmt && p_GetStringFormatFlags) p_GetStringFormatFlags(fmt,&flags);
            if(p_CreateMatrix&&p_GetWorldTransform&&p_GetMatrixElements){
                GpMatrix* m=NULL;
                if(p_CreateMatrix(&m)==0&&m){
                    if(p_GetWorldTransform(g,m)==0) p_GetMatrixElements(m,e);
                    if(p_DeleteMatrix)p_DeleteMatrix(m);
                }
            }
            trace("TIMELINE label: len=%d fs=%g rc=[%g %g %g %g] xform=[%g %g %g %g %g %g] fmt=[a%d la%d fl0x%x] hex=[%s]\n",
                  len,fs,rc?rc->X:0,rc?rc->Y:0,rc?rc->W:0,rc?rc->H:0,
                  e[0],e[1],e[2],e[3],e[4],e[5],align,linealign,(unsigned)flags,txt);
        }
    }
    /* v9: gabarit sans chiffres avec '.' et espaces -> backtrace du composeur */
    if(str && len>=3 && len<=32){
        int i,ndig=0,ndot=0,nsp=0;
        for(i=0;i<len;i++){ WCHAR c=str[i];
            if(c>=0x30&&c<=0x39) ndig++;
            else if(c==0x2e) ndot++;
            else if(c==0x20) nsp++;
        }
        if(ndig==0 && ndot>=1 && nsp>=2 && InterlockedIncrement(&c_bt)<=24)
            log_backtrace(str,len);
    }
    /* DIAGNOSTIC v8: ce DrawString suit un TranslateWorldTransform NaN sur ce thread =
     * un CHAMP VALEUR. On radiographie la police reellement utilisee + ses metriques
     * live + le contenu exact (hexa) pour identifier la police fautive / la vraie source. */
    if(g_tlsNan!=TLS_OUT_OF_INDEXES && TlsGetValue(g_tlsNan)){
        TlsSetValue(g_tlsNan,NULL);
        if(InterlockedIncrement(&c_ds2)<=40){
            char nm[48]="?"; unsigned short em=0,ca=0,cd=0; float fs=-1.0f; GpStatus se=99,sa=99;
            GpFontFamily* fam=NULL;
            if(p_GetFamily&&p_GetFamily(font,&fam)==0&&fam){
                WCHAR w[48]={0}; if(p_GetFamilyName&&p_GetFamilyName(fam,w,0)==0){int i;for(i=0;i<47&&w[i];i++)nm[i]=(w[i]<128)?(char)w[i]:'?';nm[i]=0;}
                if(p_GetEmHeight) se=p_GetEmHeight(fam,0,&em);
                if(p_GetCellAscent) sa=p_GetCellAscent(fam,0,&ca);
                if(p_GetCellDescent) p_GetCellDescent(fam,0,&cd);
            }
            if(p_GetFontSize) p_GetFontSize(font,&fs);
            /* contenu hexa (16 premiers wchar) */
            char hex[128]="", *hp=hex; int i,nn=(len>0?len:0); if(nn<=0){const WCHAR*q=str;while(q&&q[nn]&&nn<16)nn++;}
            for(i=0;i<nn&&i<16;i++){ hp+=sprintf(hp,"%04x ",(unsigned)str[i]); }
            float rx=-999,ry=-999,rw=-999,rh=-999; if(rc){rx=rc->X;ry=rc->Y;rw=rc->W;rh=rc->H;}
            trace("VALEUR draw: fam='%s' em=%u(s%d) ascent=%u(s%d) fs=%g len=%d rc=[%g %g %g %g] hex=[%s]\n",
                  nm,(unsigned)em,se,(unsigned)ca,sa,fs,len,rx,ry,rw,rh,hex);
        }
    }
    /* echantillon: chaines courtes (valeurs dynamiques type "141°") -> contenu+taille police+transform */
    if(str && len>0 && len<=8 && InterlockedIncrement(&c_ds)<=30){
        char txt[16]; int i; float fs=-1.0f; float e[6]={0};
        int n=(len<12)?len:12;
        for(i=0;i<n;i++) txt[i]=(str[i]>=32&&str[i]<127)?(char)str[i]:'?';
        txt[i]=0;
        if(p_GetFontSize) p_GetFontSize(font,&fs);
        if(p_CreateMatrix&&p_GetWorldTransform&&p_GetMatrixElements){ GpMatrix* m=NULL;
            if(p_CreateMatrix(&m)==0&&m){ if(p_GetWorldTransform(g,m)==0) p_GetMatrixElements(m,e);
                if(p_DeleteMatrix)p_DeleteMatrix(m); } }
        trace("DrawString sample: txt='%s' len=%d fontsize=%g rc={%g,%g,%g,%g} xform=[%g %g %g %g %g %g]\n",
              txt,len,fs,rc?rc->X:0,rc?rc->Y:0,rc?rc->W:0,rc?rc->H:0,e[0],e[1],e[2],e[3],e[4],e[5]);
    }
    /* FIX v13: rc des champs VALEUR = [X, NaN, W, 0] (Y NaN + hauteur 0) -> GDI+ ne peut pas
     * dessiner -> champ invisible. Les LABELS ont [X,0,W,100000] et s'affichent. On sanitise le
     * rc (Y NaN->0, H<=0->100000) pour que la valeur se dessine comme un label. Zero octet Adobe. */
    static LONG c_rcfix;
    RectF rcfix; const RectF* rcp=rc; int timeline_frame_value=0;
    if(rc && (badf(rc->X)||badf(rc->Y)||badf(rc->W)||badf(rc->H)||rc->H<=0.0f||rc->W<=0.0f)){
        rcfix=*rc;
        /* P11 Timeline T1. Les nombres FPS/Frame ont une ancre de bord droit:
         * xform.Y=7.5, rc=[rightEdge,NaN,0,0]. Le fallback historique les
         * dessinait à partir de rightEdge dans une boîte de 100000 px, donc
         * exactement par-dessus les labels FPS/F situés 3 px plus loin.
         * Mesurer le texte avec le vrai GDI+, puis reconstruire une boîte finie
         * se terminant sur cette ancre. Le test Y limite le changement à la
         * rangée compteur de la Timeline; les autres champs gardent v15. */
        int timeline_value=0;
        float tw=0.0f,th=0.0f,wy=-999.0f;
        if(str && font && rc->W<=0.0f && rc->H<=0.0f &&
           p_CreateMatrix&&p_GetWorldTransform&&p_GetMatrixElements){
            GpMatrix* m=NULL; float e[6]={0};
            if(p_CreateMatrix(&m)==0&&m){
                if(p_GetWorldTransform(g,m)==0&&p_GetMatrixElements(m,e)==0) wy=e[5];
                if(p_DeleteMatrix)p_DeleteMatrix(m);
            }
            if(wy>=7.0f&&wy<=8.0f&&p_MeasureString){
                RectF probe={0,0,1000,1000},bound={0,0,0,0};
                if(p_MeasureString(g,str,len,font,&probe,fmt,&bound,NULL,NULL)==0 &&
                   !badf(bound.W)&&!badf(bound.H)&&bound.W>0.0f&&bound.H>0.0f){
                    tw=bound.W; th=bound.H; timeline_value=1;
                }
            }
        }
        if(badf(rcfix.X)) rcfix.X=0.0f;
        if(badf(rcfix.Y)) rcfix.Y=0.0f;
        if(timeline_value){
            if(rc->X>=1.5f&&rc->X<=2.5f){
                /* T6 : le gabarit est "F     .". La surface valeur fait 54 px
                 * et commence à -1.5 : placer le nombre à X=18, donc après le
                 * F, avec une boîte fixe. Aucune coordonnée négative et aucun
                 * déplacement selon le nombre de chiffres. */
                rcfix.X=18.0f;
                rcfix.W=34.0f;
                rcfix.H=th+1.0f;
            }else{
                rcfix.X-=tw;
                rcfix.W=tw+1.0f;
                rcfix.H=th+1.0f;
            }
            /* Le compteur Frame est identifié par son ancre historique X=2. */
            if(rc->X>=1.5f&&rc->X<=2.5f){
                timeline_frame_value=1;
            }
            if(InterlockedIncrement(&c_timeline_fix)<=40)
                trace("TIMELINE_FIX: wy=%g anchor=%g measured=[%g %g] -> [%g %g %g %g]\n",
                      wy,rc->X,tw,th,rcfix.X,rcfix.Y,rcfix.W,rcfix.H);
        }else{
            if(badf(rcfix.W)||rcfix.W<=0.0f) rcfix.W=100000.0f;
            if(badf(rcfix.H)||rcfix.H<=0.0f) rcfix.H=100000.0f;
        }
        rcp=&rcfix;
        if(InterlockedIncrement(&c_rcfix)<=30) trace("RC_FIX: [%g %g %g %g] -> [%g %g %g %g]\n",rc->X,rc->Y,rc->W,rc->H,rcfix.X,rcfix.Y,rcfix.W,rcfix.H);
    }
    /* T6 : nettoyer puis repeindre la réserve fixe située après le label F,
     * dans la surface valeur native de 54 px. */
    if(timeline_frame_value&&p_SaveGraphics&&p_RestoreGraphics&&
       p_CreateSolidFill&&p_FillRectangle&&p_DeleteBrush&&p_DrawString){
        unsigned int state=0; void* bg=NULL;
        if(p_SaveGraphics(g,&state)==0){
            if(p_CreateSolidFill(0xff323232u,&bg)==0&&bg){
                p_FillRectangle(g,bg,14.0f,-2.0f,39.0f,22.0f);
                p_DeleteBrush(bg);
            }
            GpStatus ts=p_DrawString(g,str,len,font,rcp,fmt,brush);
            p_RestoreGraphics(g,state);
            if(ts==0) return 0;
        }
    }
    GpStatus s=p_DrawString?p_DrawString(g,str,len,font,rcp,fmt,brush):18;
    if(s==0) return 0;
    if(g&&p_CreateMatrix&&p_GetWorldTransform&&p_GetMatrixElements&&p_ResetWorldTransform&&p_SetWorldTransform){
        GpMatrix* m=NULL;
        if(p_CreateMatrix(&m)==0&&m){ float e[6]={0}; int bad=0;
            if(p_GetWorldTransform(g,m)==0){ p_GetMatrixElements(m,e); for(int i=0;i<6;i++) if(badf(e[i])) bad=1;
                if(bad){ p_ResetWorldTransform(g); GpStatus sd=p_DrawString(g,str,len,font,rcp,fmt,brush); p_SetWorldTransform(g,m);
                    if(sd==0){ InterlockedIncrement(&g_fixed); if(p_DeleteMatrix)p_DeleteMatrix(m); return 0; } } }
            if(p_DeleteMatrix)p_DeleteMatrix(m); }
    }
    InterlockedIncrement(&g_failopen); return 0;
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD r,LPVOID x){(void)x;
    if(r==DLL_PROCESS_ATTACH){ DisableThreadLibraryCalls(h); g_tlsNan=TlsAlloc(); }
    return TRUE;}
