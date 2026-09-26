"""Generate the third Drillbit direction as an editable SVG board for Figma."""
from pathlib import Path
import html, math, random

OUT = Path(__file__).resolve().parent / 'drillbit-signal-app-board.svg'
W, H = 390, 844
C = {
    'floor':'#1F2430', 'surface':'#232834', 'raised':'#2A303E',
    'line':'#414C5D', 'text':'#F3F4F6', 'muted':'#ADB4C0',
    'dim':'#778396', 'yellow':'#FFCC65', 'yellowSoft':'#F4C46B',
    'grain':'#D8D6CF', 'warmGrain':'#FFE2A3',
}

def T(x,y,txt,size=16,fill=None,weight=400,tracking=0,anchor=None,mono=False):
    fill=fill or C['text']; fam='SFMono-Regular, Menlo, monospace' if mono else 'SF Pro Display, -apple-system, Helvetica Neue, Arial, sans-serif'
    at=f'x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{weight}" fill="{fill}" letter-spacing="{tracking}"'
    if anchor:at+=f' text-anchor="{anchor}"'
    lines=str(txt).split('\n')
    if len(lines)==1:
        return '<text '+at+'>'+html.escape(lines[0])+'</text>'
    return ''.join('<text '+at.replace(f'y="{y}"', f'y="{y + i*size*1.16:.1f}"')+'>'+html.escape(v)+'</text>' for i,v in enumerate(lines))
def R(x,y,w,h,fill,r=0,stroke=None,sw=1,opacity=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" opacity="{opacity}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def O(x,y,r,fill,opacity=1,stroke=None,sw=1):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="{opacity}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def L(x1,y1,x2,y2,color=None,sw=1,opacity=1,dash=None):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color or C["line"]}" stroke-width="{sw}" opacity="{opacity}"'+(f' stroke-dasharray="{dash}"' if dash else '')+'/>'
def wave(cx,cy,width=130,active=True):
    s='';n=33
    for i in range(n):
        x=cx-width/2+i*width/(n-1)
        h=(4+21*abs(math.sin(i*.35)**3)) if active else 3
        if 10<i<23:h*=.52
        s+=L(round(x,1),round(cy-h/2,1),round(x,1),round(cy+h/2,1),C['yellowSoft'],2.3 if active else 1.4,.9 if active else .6)
    return s

def particles(cx,cy,rx,ry,n,seed=1,energy=1):
    rng=random.Random(seed);s=''
    for i in range(n):
        a=rng.random()*math.tau
        # Dense central volume and a sparse outer halo, with frequency-like radial strata.
        band=rng.random()
        radial=min(1.3, max(.05,rng.gauss(.58,.29)))
        x=cx+math.cos(a)*rx*radial+rng.gauss(0,rx*.018)
        y=cy+math.sin(a)*ry*radial+rng.gauss(0,ry*.018)
        warm=radial<.5 or (rng.random()<.14 and radial<.9)
        color=C['yellowSoft'] if warm else C['grain']
        if radial>1.0:color=C['dim']
        op=max(.12,(.78-.36*radial)*rng.uniform(.68,1.1))*energy
        r=.45+rng.random()*.6
        if band>.95:r*=1.35
        s+=O(round(x,1),round(y,1),round(r,2),color,round(min(op,.95),2))
    return s

def mark(x,y):
    return R(x,y,31,31,C['surface'],9)+O(x+12,y+13,5,C['yellow'])+O(x+19,y+10,2.8,C['warmGrain'])+O(x+20,y+18,1.9,C['grain'])
def base():
    return R(0,0,W,H,C['floor'],45)+R(0,0,W,120,'url(#top)',45,opacity=.55)+T(28,38,'9:41',15,weight=600)+R(163,16,64,21,'#0B0C10',11)+T(337,37,'●  ▰',12,weight=600,anchor='middle')
def top(title=None,close=False,right=None):
    s=''
    if title is None:s+=mark(26,74)+T(67,96,'drillbit',17,weight=650,tracking=-.5)
    else:
        s+=O(47,92,20,C['raised'])+T(47,100,'×' if close else '‹',27,weight=300,anchor='middle')
        s+=T(195,99,title,14,C['muted'],550,anchor='middle')
    if right:s+=T(359,97,right,12,C['muted'],500,anchor='end',mono=True)
    return s

def btn(label,y=742,secondary=None):
    s=R(24,y,342,56,C['yellow'],28)+T(195,y+35,label,15,C['floor'],650,anchor='middle')
    if secondary:s+=T(195,y-22,secondary,12,C['muted'],anchor='middle')
    return s

def voice_button(x,y,label,icon,active=False,width=80):
    bg=C['yellow'] if active else C['raised'];fg=C['floor'] if active else C['text']
    mid=x+width/2
    s=R(x,y,width,54,bg,27,C['line'] if not active else None,.7)
    if icon=='type':
        s+=R(mid-12,y+19,24,17,'none',4,fg,1.6)
        for xx in (-7,-2,3,8):s+=O(mid+xx,y+25,1,fg)
        s+=L(mid-7,y+31,mid+7,y+31,fg,1.5)
    elif icon=='mute':
        s+=R(mid-4,y+14,8,17,fg,4)
        s+=f'<path d="M {mid-10} {y+28} A 10 10 0 0 0 {mid+10} {y+28}" fill="none" stroke="{fg}" stroke-width="2"/>'
        s+=L(mid,y+37,mid,y+41,fg,2)+L(mid-6,y+41,mid+6,y+41,fg,2)
    elif icon=='finish':
        s+=R(mid-8,y+19,16,16,fg,4)
    s+=T(mid,y+74,label,11,C['muted'],500,anchor='middle')
    return s

def welcome():
    s=base()+top()
    s+=particles(195,349,146,133,1450,21)+wave(195,351,106,False)
    s+=T(27,545,'SYSTEM DESIGN / OUT LOUD',10,C['yellow'],650,1.6,mono=True)
    s+=T(27,601,'A better answer\nstarts in motion.',35,weight=650,tracking=-1.3)
    s+=T(27,701,'An AI interviewer for five spare minutes.',14,C['muted'])
    s+=btn('Start practicing',746)
    return s

def home():
    s=base()+top(right='TODAY')
    s+=T(28,166,'THE NEXT QUESTION',10,C['yellow'],650,1.5,mono=True)
    s+=T(28,224,'What if the\nrequest timed out?',33,weight=650,tracking=-1.1)
    s+=T(28,323,'You may have sent the receipt.\nYour interviewer will push on retries.',15,C['muted'])
    # one open diagram, no card
    s+=L(49,415,49,595,C['yellow'],1.3,.7)+O(49,421,5,C['yellow'])+O(49,507,4,C['yellow'],.75)+O(49,590,5,C['yellow'])
    s+=T(75,426,'Send request',17,weight=550)+T(75,451,'Receipt delivery begins',12,C['muted'])
    s+=T(75,512,'Timeout',17,weight=550)+T(75,537,'The result is unknown',12,C['muted'])
    s+=T(75,595,'Retry safely',17,C['yellow'],600)+T(75,620,'One operation, one receipt',12,C['muted'])
    s+=btn('Start 5-minute interview',691)
    s+=L(27,774,363,774,opacity=.45)+T(28,815,'02 ideas in Recall',13,C['muted'])+T(358,815,'↗',19,C['yellow'],anchor='end')
    return s

def brief():
    s=base()+top('Before you begin',right='05 MIN')
    s+=T(28,172,'THE SCENARIO',10,C['yellow'],650,1.6,mono=True)
    s+=T(28,234,'One receipt.\nUncertain delivery.',35,weight=650,tracking=-1.1)
    s+=T(28,348,'A send request times out. It may already\nhave succeeded. How do you retry?',15,C['muted'])
    # compact visual reasoning line
    s+=L(51,462,339,462,C['line'],1.6)
    for x,label,note in [(52,'SEND','01'),(195,'WAIT','02'),(339,'RETRY','03')]:
        s+=O(x,462,13,C['surface'],1,C['yellow'] if x!=195 else C['line'],1.4)
        s+=O(x,462,3,C['yellow'] if x!=195 else C['muted'])
        s+=T(x,504,label,11,C['text'],600,anchor='middle',mono=True)+T(x,523,note,10,C['dim'],anchor='middle',mono=True)
    s+=L(27,584,363,584,opacity=.6)
    s+=T(28,622,'You lead with what you would clarify.',16,weight=550)
    s+=T(28,654,'Speak naturally; switch to type anytime.',13,C['muted'])
    s+=btn('Enter interview',746)
    return s

def voice():
    s=base()+top('Interview',close=True,right='02:14')
    s+=T(28,161,'NOTIFICATION DELIVERY',10,C['yellow'],650,1.5,mono=True)
    s+=T(28,207,'How would you prevent\nduplicate sends?',24,weight=600,tracking=-.6)
    s+=L(28,268,362,268,opacity=.55)
    s+=particles(195,447,150,140,1950,44)+wave(195,447,132,True)
    s+=T(195,607,'LISTENING',11,C['yellow'],650,1.7,anchor='middle',mono=True)
    s+=T(195,634,'Your answer is being captured',12,C['muted'],anchor='middle')
    s+=L(28,688,362,688,opacity=.55)
    s+=voice_button(36,711,'Type','type',False,80)
    s+=voice_button(137,704,'Mute','mute',True,116)
    s+=voice_button(274,711,'Finish','finish',False,80)
    return s

def reflection():
    s=base()+top('Reflection',right='DONE')
    s+=T(28,169,'FROM THIS ANSWER',10,C['yellow'],650,1.5,mono=True)
    s+=T(28,230,'“I’d retry when\nit times out.”',29,weight=570,tracking=-.7)
    s+=L(29,292,360,292,C['yellow'],2,.8)
    s+=T(28,346,'THE MISSING GUARD',10,C['muted'],650,1.5,mono=True)
    s+=T(28,407,'Keep the same\nrequest ID.',34,weight=650,tracking=-1.1)
    s+=T(28,505,'If the first send succeeded, the retry\nshould return that result without sending again.',15,C['muted'])
    s+=L(29,580,29,668,C['yellow'],2)
    s+=T(48,608,'TRY IT AGAIN',11,C['yellow'],650,1.3,mono=True)
    s+=T(48,647,'Say where the ID is stored and\nhow long it remains valid.',15)
    s+=btn('Practice this moment',737)
    s+=T(195,826,'Added to Recall',12,C['muted'],anchor='middle')
    return s

def recall():
    s=base()+top('Recall',right='01 / 02')
    s+=T(28,169,'FROM YOUR INTERVIEW',10,C['yellow'],650,1.5,mono=True)
    s+=T(28,236,'A timeout is not\na failed send.',34,weight=650,tracking=-1.1)
    s+=particles(195,426,116,93,680,75,.87)+wave(195,427,76,False)
    s+=T(28,579,'What lets a retry discover\nthe first result?',18,weight=520)
    s+=T(28,665,'THINK BEFORE REVEALING',10,C['muted'],650,1.3,mono=True)
    s+=btn('Reveal the idea',745)
    return s

def system():
    s=R(0,0,W,H,C['floor'],45)
    s+=T(28,81,'SIGNAL / LANGUAGE',11,C['yellow'],650,1.7,mono=True)
    s+=T(28,135,'One live idea\nat a time.',31,weight=650,tracking=-1)
    s+=T(28,222,'Hierarchy',20,weight=600)+L(28,243,362,243,opacity=.5)
    for y,n,title,note in [(282,'01','The question','Always readable above the field'),(372,'02','The presence','12 bands shape local particle motion'),(462,'03','The control','Start, mute, type and finish are explicit'),(552,'04','The learning','Feedback and Recall use answer evidence')]:
        s+=T(28,y,n,12,C['yellow'],600,mono=True)+T(67,y,title,18,weight=580)+T(67,y+23,note,12,C['muted'])
    s+=T(28,645,'COLOR ROLES',10,C['yellow'],650,1.5,mono=True)
    for i,(key,label) in enumerate([('floor','Field'),('surface','Depth'),('text','Ink'),('muted','Secondary'),('yellow','Voice')]):
        x=28+i*69;s+=R(x,665,55,46,C[key],10,C['line'],.5)+T(x,729,label,10,C['muted'],anchor=None)
    s+=L(28,765,362,765,opacity=.5)
    s+=T(28,797,'Reduced Motion',14,weight=600)+T(28,819,'Freeze shape; retain waveform and state text.',11,C['muted'])
    return s

def board():
    bw,bh=1580,2260
    s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{bw}" height="{bh}" viewBox="0 0 {bw} {bh}">'
    s+='''<defs><linearGradient id="top" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#343B4B"/><stop offset="1" stop-color="#1F2430"/></linearGradient></defs>'''
    s+=R(0,0,bw,bh,'#141820')
    s+=T(60,76,'DRILLBIT  /  THIRD DIRECTION',12,C['yellow'],650,2,mono=True)
    s+=T(60,135,'SIGNAL',52,weight=680,tracking=-2)
    s+=T(60,171,'The particle interviewer, grounded in the original yellow. One question leads; one conversation moves into learning.',17,C['muted'])
    s+=L(60,212,1520,212,C['line'],1)
    screens=[('01  WELCOME',welcome),('02  HOME',home),('03  SESSION BRIEF',brief),('04  VOICE ROOM',voice),('05  REFLECTION',reflection),('06  DESIGN RULES',system)]
    for i,(name,make) in enumerate(screens):
        col,row=i%3,i//3;x=60+col*490;y=304+row*963
        s+=T(x,y-19,name,12,C['yellow'],650,1.5,mono=True)
        s+=f'<g transform="translate({x},{y})">{make()}</g>'
    s+=T(60,2170,'VOICE STATES',11,C['yellow'],650,1.6,mono=True)
    s+=T(60,2200,'READY   ·   LISTENING   ·   THINKING   ·   SPEAKING   ·   MUTED   ·   RECONNECTING',13,C['muted'],500,1.3,mono=True)
    s+=T(60,2231,'CONCEPT STUDY  /  STATIC FIGMA VIEW  /  PARTICLE MOTION IS SPECIFIED IN ORB LAB',10,C['dim'],500,1.3,mono=True)
    return s+'</svg>'

OUT.write_text(board())
print(OUT, OUT.stat().st_size)
