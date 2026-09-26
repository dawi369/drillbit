import math, random, html, os
from pathlib import Path

OUT=Path(__file__).resolve().parent
OUT.mkdir(parents=True,exist_ok=True)
W,H=390,844
GAP_X,GAP_Y=86,132
BOARD_W=3*W+4*GAP_X
BOARD_H=3*(H+42)+4*GAP_Y+176

SCREENS=['Welcome','Focus','Home','Session brief','Voice room','Feedback','Recall','Library','Settings']
COPY={
'Welcome':('Practice out loud.','An interviewer for the moments in between.','Start practicing'),
'Focus':('What are you\nworking on?','Choose a starting point. Change it anytime.','Continue'),
'Home':('A little practice\ngoes a long way.','Your next conversation','Start 5 min'),
'Session brief':('Design a notification\nsystem.','Deliver each message once, even when requests retry.','Start interview'),
'Voice room':('','Listening','Finish'),
'Feedback':('You found the\nright question.','A stronger next move','Continue'),
'Recall':('What makes a\nretry safe?','Think it through','Reveal answer'),
'Library':('Your practice,\nin one place.','Recent conversations','Open session'),
'Settings':('Make it yours.','Practice preferences','Save changes'),
}

def esc(t): return html.escape(str(t),quote=True)
def text(x,y,s,size=16,color='#F3F3F3',weight=400,spacing=0,anchor=None,mono=False,opacity=1):
    family='SFMono-Regular, Menlo, monospace' if mono else 'SF Pro Display, -apple-system, BlinkMacSystemFont, Helvetica Neue, Arial, sans-serif'
    attrs=f'x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{color}" letter-spacing="{spacing}" opacity="{opacity}"'
    if anchor: attrs+=f' text-anchor="{anchor}"'
    lines=str(s).split('\n')
    if len(lines)==1:return f'<text {attrs}>{esc(s)}</text>'
    return f'<text {attrs}>'+''.join(f'<tspan x="{x}" dy="{0 if i==0 else size*1.12}">{esc(line)}</tspan>' for i,line in enumerate(lines))+'</text>'
def rect(x,y,w,h,fill,r=0,stroke=None,sw=1,opacity=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+f' opacity="{opacity}"/>'
def circle(x,y,r,fill,opacity=1,stroke=None,sw=1):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="{opacity}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def line(x1,y1,x2,y2,c,sw=1,opacity=1,dash=None):
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{c}" stroke-width="{sw}" opacity="{opacity}"'+(f' stroke-dasharray="{dash}"' if dash else '')+'/>'
def pill(x,y,w,label,c,fg='#161616',outline=False):
    return rect(x,y,w,44,'none' if outline else c,22,c if outline else None)+text(x+w/2,y+28,label,14,fg if not outline else c,600,anchor='middle')
def phone_base(theme):
    bg='#1D1D1D' if theme=='particle' else '#202530'
    return rect(0,0,W,H,bg,50)+rect(0,0,W,H,'url(#particleBg)' if theme=='particle' else 'url(#orangeBg)',50,opacity=.78)+text(29,38,'9:41',15,'#F5F5F5',600)+text(321,38,'●  ▰',12,'#F5F5F5',600)+rect(163,16,65,21,'#0A0A0A',11)
def header(theme,title=None,back=False):
    ink='#F2F2F1' if theme=='particle' else '#EDEFF2'
    sub='#A8A8A8' if theme=='particle' else '#ADB4C0'
    accent='#F0817B' if theme=='particle' else '#E8C17D'
    s=''
    if back:
        s+=circle(46,102,22,'#414141' if theme=='particle' else '#303743',1)+text(46,110,'×' if title=='Voice room' else '‹',29,ink,300,anchor='middle')
        if title!='Voice room':s+=text(195,109,title,15,sub,500,anchor='middle')
    else:
        s+=circle(40,95,7,accent)+circle(48,89,3,ink,.8)+circle(51,100,2.2,ink,.6)
        s+=text(62,102,'drillbit',17,ink,650,-.6)
        if title=='Home':s+=circle(348,95,19,'#3D3D3D' if theme=='particle' else '#303743')+text(348,101,'⌕',17,sub,anchor='middle')
    return s

def cloud(cx,cy,rx,ry,n,seed=7,scale=1,accent=None):
    rng=random.Random(seed); s=''
    for i in range(n):
        a=rng.random()*math.tau; radial=min(1.25,abs(rng.gauss(.55,.31)))
        # denser center and a dissolving halo
        xx=cx+math.cos(a)*rx*radial+rng.gauss(0,rx*.035)
        yy=cy+math.sin(a)*ry*radial+rng.gauss(0,ry*.035)
        op=(.12+.55*(1-min(radial,1)))*rng.uniform(.45,1)
        r=(.36+rng.random()*.55)*scale
        s+=circle(round(xx,1),round(yy,1),round(r,2),accent or '#D4D4D4',round(op,2))
    return s

def waveform(x,y,width,theme,active=False):
    c='#A2A2A2' if theme=='particle' else '#E8C17D';s=''
    count=29
    for i in range(count):
        xx=x+i*width/(count-1)
        amp=(2+11*abs(math.sin(i*.43)**4)) if active else (1.5+2*abs(math.sin(i*.46)))
        if 11<i<18:amp*=.65
        s+=line(round(xx,1),round(y-amp/2,1),round(xx,1),round(y+amp/2,1),c,2 if active else 1.7,.7)
    return s

def contour(cx,cy,rad,theme,opacity=1):
    s=''
    for j in range(9):
        pts=[]
        for k in range(101):
            a=k*math.tau/100
            r=rad+j*4+4*math.sin(a*5+j*.35)+2*math.cos(a*11-j*.27)
            pts.append(f'{cx+r*math.cos(a):.1f},{cy+r*.67*math.sin(a):.1f}')
        s+=f'<polyline points="{" ".join(pts)}" fill="none" stroke="{["#FFE2A3","#D4A355","#A97838"][j%3]}" stroke-width="1.1" opacity="{opacity*(.45-j*.028):.2f}"/>'
    return s

def agent(cx,cy,theme,size='large'):
    if theme=='particle':
        n=480 if size=='large' else 210
        s=cloud(cx,cy,148 if size=='large' else 92,145 if size=='large' else 86,n,seed=int(cx+cy),scale=.9)
        if size=='large':s+=waveform(cx-87,cy,174,theme,True)
        return s
    s=contour(cx,cy,98 if size=='large' else 58,theme)
    if size=='large':s+=waveform(cx-55,cy,110,theme,True)
    return s

def footer(theme,selected='Home'):
    c='#B0B0B0' if theme=='particle' else '#ADB4C0';a='#F0817B' if theme=='particle' else '#E8C17D'
    s=line(24,775,366,775,c,1,.18)
    for x,label,icon in [(70,'Home','⌂'),(195,'Recall','◎'),(320,'Library','▤')]:
        z=a if label==selected else c
        s+=text(x,804,icon,23,z,400,anchor='middle')+text(x,824,label,10,z,500,anchor='middle')
    return s

def button(theme,label,y=727,w=342,x=24):
    a='#F0817B' if theme=='particle' else '#E8C17D'; fg='#241A19' if theme=='particle' else '#28261F'
    return rect(x,y,w,54,a,27)+text(x+w/2,y+34,label,15,fg,650,anchor='middle')

def screen(name,theme):
    a='#F0817B' if theme=='particle' else '#E8C17D'
    fg='#F2F2F1' if theme=='particle' else '#EDEFF2'
    muted='#A2A2A2' if theme=='particle' else '#ADB4C0'
    faint='#777777' if theme=='particle' else '#778294'
    surface='#353535' if theme=='particle' else '#303743'
    s=phone_base(theme)
    if name=='Welcome':
        s+=header(theme)
        s+=agent(195,356,theme)
        s+=text(28,562,'SYSTEM DESIGN · OUT LOUD',10,a,650,1.8,mono=True)
        s+=text(28,612,'Practice the answer\nyou’ll actually say.',32,fg,650,-1.15)
        s+=text(28,701,'Short conversations. Useful follow-ups.',14,muted)
        s+=button(theme,'Meet your interviewer',746)
    elif name=='Focus':
        s+=header(theme,'Focus',True)+text(28,184,'01 / 02',11,a,550,1.8,mono=True)
        s+=text(28,241,'What are you\nworking on?',35,fg,650,-1.4)
        s+=text(28,342,'Pick a starting point.',15,muted)
        for i,(v,sub) in enumerate([('System design','Architecture · tradeoffs'),('Coding interview','Patterns · reasoning'),('Just exploring','Find a rhythm')]):
            y=397+i*84
            s+=rect(24,y,342,68,surface if i==0 else 'none',15,a if i==0 else '#777777',1 if i==0 else .5,1 if i==0 else .5)
            s+=text(46,y+28,v,17,fg,600)+text(46,y+49,sub,11,muted)+text(338,y+37,'✓' if i==0 else '○',18,a if i==0 else faint,anchor='middle')
        s+=button(theme,'Continue',746)
    elif name=='Home':
        s+=header(theme,'Home')
        s+=text(28,172,'TODAY / 05 MIN',11,a,650,1.7,mono=True)
        s+=text(28,232,'A little practice\ngoes a long way.',32,fg,650,-1.25)
        s+=agent(196,415,theme,'small')
        s+=text(28,558,'NEXT CONVERSATION',10,muted,600,1.4,mono=True)
        s+=text(28,599,'Notification delivery',24,fg,600,-.65)
        s+=text(28,624,'Keep retries safe without duplicate sends.',13,muted)
        s+=button(theme,'Start 5 min',661)
        s+=text(28,750,'02',22,a,550)+text(70,750,'ideas waiting in Recall',14,muted)
        s+=footer(theme)
    elif name=='Session brief':
        s+=header(theme,'Session',True)+text(28,176,'01 / QUESTION',11,a,600,1.7,mono=True)
        s+=text(28,245,'Design a notification\nsystem.',34,fg,650,-1.25)
        s+=text(28,352,'A receipt must reach the customer once.\nThe sender may retry after a timeout.',15,muted)
        s+=line(28,402,362,402,a,1,.5)
        s+=text(28,446,'THE INTERVIEWER WILL ASK',10,muted,600,1.3,mono=True)
        s+=text(28,487,'What would you clarify first?',21,fg,530,-.45)
        s+=text(28,571,'▧  5 min      ◉  Voice first',13,muted)
        s+=text(28,610,'You can type at any point.',13,muted)
        s+=button(theme,'Start interview',746)
    elif name=='Voice room':
        s+=header(theme,'Voice room',True)
        # sparse stars / field texture
        rng=random.Random(24)
        if theme=='particle':
            for i in range(125):
                x=rng.random()*390;y=145+rng.random()*540
                s+=circle(round(x,1),round(y,1),rng.choice([.35,.5,.7]),'#BEBEBE',rng.uniform(.08,.31))
        s+=agent(195,385,theme)
        s+=text(195,593,'LISTENING',10,a,650,1.7,anchor='middle',mono=True)
        s+=text(195,681,'0:06',19,muted,450,anchor='middle')
        s+=circle(195,750,47,'#414141' if theme=='particle' else '#303743',1,'#5B5B5B',1)
        s+=rect(182,737,26,26,a,6)
        s+=text(328,120,'···',24,muted,anchor='middle')
    elif name=='Feedback':
        s+=header(theme,'Feedback',True)+text(28,171,'SESSION COMPLETE',11,a,650,1.7,mono=True)
        s+=text(28,239,'You found the\nright question.',35,fg,650,-1.3)
        s+=text(28,351,'You asked about delivery guarantees\nbefore choosing a queue.',15,muted)
        s+=line(28,409,362,409,a,1,.55)
        s+=text(28,452,'NEXT TIME',10,a,650,1.6,mono=True)
        s+=text(28,496,'Name the idempotency key.',23,fg,600,-.5)
        s+=text(28,534,'Use the same key on every retry so\none action cannot create two receipts.',14,muted)
        s+=rect(28,590,4,93,a,2)+text(49,612,'FROM YOUR ANSWER',10,muted,600,1.2,mono=True)
        s+=text(49,647,'“I would retry when it times out.”',15,fg)
        s+=text(49,672,'Evidence tied to your transcript',12,muted)
        s+=button(theme,'Practice this moment',746)
    elif name=='Recall':
        s+=header(theme,'Recall',True)+text(28,172,'FROM YOUR PRACTICE · 01 / 02',10,a,600,1.25,mono=True)
        s+=text(28,244,'What makes a\nretry safe?',36,fg,650,-1.3)
        s+=agent(195,434,theme,'small')
        s+=text(28,557,'A request times out. It may already\nhave succeeded. What prevents a repeat?',15,muted)
        s+=text(28,664,'THINK FIRST, THEN REVEAL',10,muted,600,1.2,mono=True)
        s+=button(theme,'Reveal answer',746)
    elif name=='Library':
        s+=header(theme,'Library',True)+text(28,184,'Your practice,\nin one place.',33,fg,650,-1.2)
        s+=text(28,287,'RECENT CONVERSATIONS',10,a,600,1.5,mono=True)
        for i,(title,tag,date) in enumerate([('Notification delivery','System design','Today'),('Repeated events','Coding · 8 min','Tuesday'),('Rate limiting','System design','Monday')]):
            y=331+i*122
            s+=line(28,y-18,362,y-18,muted,1,.3)
            s+=circle(45,y+23,15,surface)+text(45,y+29,'•',19,a,anchor='middle')
            s+=text(74,y+18,title,18,fg,600)+text(74,y+43,tag,12,muted)+text(362,y+43,date,11,faint,anchor='end')
        s+=text(28,722,'Every session leaves something to revisit.',13,muted)
        s+=footer(theme,'Library')
    elif name=='Settings':
        s+=header(theme,'Settings',True)+text(28,189,'Make it yours.',35,fg,650,-1.25)
        s+=text(28,256,'PRACTICE',10,a,650,1.5,mono=True)
        for i,(title,value) in enumerate([('Interview mode','Guided'),('Session length','5 minutes'),('Default input','Voice'),('Daily reminder','Off')]):
            y=306+i*81
            s+=line(28,y-24,362,y-24,muted,1,.25)+text(28,y+2,title,17,fg,500)+text(360,y+2,value+'  ›',13,muted,anchor='end')
        s+=text(28,658,'ACCOUNT',10,a,650,1.5,mono=True)
        s+=line(28,681,362,681,muted,1,.25)+text(28,713,'Privacy & data',17,fg,500)+text(360,713,'›',17,muted,anchor='end')
        s+=text(28,768,'Sign out',15,muted)
    return s

def board(theme):
    name='PARTICLE / VOICE PRESENCE' if theme=='particle' else 'MIRAGE / AMBER CONTOUR'
    a='#F0817B' if theme=='particle' else '#E8C17D'
    boardbg='#111111' if theme=='particle' else '#151A23'
    s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{BOARD_W}" height="{BOARD_H}" viewBox="0 0 {BOARD_W} {BOARD_H}">'
    s+='''<defs><linearGradient id="particleBg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#414141"/><stop offset=".57" stop-color="#292929"/><stop offset="1" stop-color="#181818"/></linearGradient><linearGradient id="orangeBg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#292F3A"/><stop offset="1" stop-color="#202530"/></linearGradient></defs>'''
    s+=rect(0,0,BOARD_W,BOARD_H,boardbg)
    s+=text(GAP_X,84,'DRILLBIT  /  DESIGN STUDY',13,a,700,2.2,mono=True)
    s+=text(GAP_X,140,name,42,'#F2F2F1',650,-1.3)
    s+=text(GAP_X,177,'Nine matching product moments · compare hierarchy, identity and conversation flow',16,'#9E9E9E')
    for i,name in enumerate(SCREENS):
        col,row=i%3,i//3
        x=GAP_X+col*(W+GAP_X); y=220+GAP_Y+row*(H+42+GAP_Y)
        s+=text(x,y-18,f'{i+1:02d}  /  {name.upper()}',12,a,650,1.35,mono=True)
        s+=f'<g transform="translate({x},{y})">'+screen(name,theme)+'</g>'
    s+=text(GAP_X,BOARD_H-43,'DRILLBIT  ·  CONCEPT ONLY  /  VOICE + FEEDBACK STATES ARE ILLUSTRATIVE',11,'#777777',500,1.2,mono=True)
    return s+'</svg>'

for theme in ('particle','orange'):
    p=OUT/f'drillbit-{theme}-app-board.svg';p.write_text(board(theme))
    print(p, p.stat().st_size)

def text_handoff(theme):
    a='#F0817B' if theme=='particle' else '#E8C17D';fg='#F2F2F1' if theme=='particle' else '#EDEFF2';muted='#A2A2A2' if theme=='particle' else '#ADB4C0';surface='#333333' if theme=='particle' else '#303743'
    s=phone_base(theme)+header(theme,'Interview',True)
    s+=text(28,175,'NOTIFICATION DELIVERY',10,a,650,1.5,mono=True)
    s+=text(28,243,'The request\ntimed out.',36,fg,650,-1.4)
    s+=text(28,359,'How do you retry without sending\na second receipt?',21,fg,500,-.4)
    s+=text(28,442,'INTERVIEWER',10,muted,600,1.4,mono=True)
    s+=text(28,478,'Tell me what you would check first.',16,fg)
    s+=line(28,524,362,524,muted,1,.3)
    s+=rect(22,568,346,193,surface,20,'#555555',.7)
    s+=text(42,603,'YOUR ANSWER',10,a,650,1.2,mono=True)
    s+=text(42,642,'I’d ask whether the delivery API\naccepts an idempotency key…',16,fg)
    s+=text(44,736,'⌕  Switch to voice',12,muted)+circle(334,728,20,a)+text(334,735,'↑',18,'#241A19',600,anchor='middle')
    s+=text(195,808,'Draft saved locally',11,muted,anchor='middle')
    return s

def handoff_board():
    bw=1080; bh=1185;s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{bw}" height="{bh}" viewBox="0 0 {bw} {bh}">'
    s+='''<defs><linearGradient id="particleBg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#414141"/><stop offset=".57" stop-color="#292929"/><stop offset="1" stop-color="#181818"/></linearGradient><linearGradient id="orangeBg" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#292F3A"/><stop offset="1" stop-color="#202530"/></linearGradient></defs>'''
    s+=rect(0,0,bw,bh,'#121212')+text(60,76,'10 / VOICE ↔ TYPE',34,'#F2F2F1',650,-1)+text(60,113,'Same conversation. One shared context. A draft remains available when the voice room ends.',15,'#A2A2A2')
    for i,(theme,x) in enumerate([('particle',80),('orange',610)]):
        s+=text(x,175,theme.upper(),12,'#F0817B' if i==0 else '#E8C17D',650,1.5,mono=True)
        s+=f'<g transform="translate({x},197)">{text_handoff(theme)}</g>'
    s+=text(60,1112,'INTERACTION RULE',11,'#F0817B',650,1.6,mono=True)+text(60,1142,'Mic and typing share a transcript; pause/stop are explicit; reconnection never appears as listening.',15,'#A2A2A2')
    return s+'</svg>'

p=OUT/'drillbit-voice-type-handoff.svg';p.write_text(handoff_board());print(p,p.stat().st_size)

def system_board():
    bw,bh=1514,1140;s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{bw}" height="{bh}" viewBox="0 0 {bw} {bh}">'
    s+=rect(0,0,bw,bh,'#141414')+text(70,82,'PARTICLE  /  DESIGN LANGUAGE',38,'#F2F2F1',650,-1)+text(70,116,'Voice is a silver field. Coral identifies one active action. Text stays sparse and precise.',17,'#A2A2A2')
    colors=[('#414141','Upper field'),('#373737','Upper depth'),('#262626','Lower field'),('#181818','Floor'),('#D4D4D4','Near grain'),('#8C8C8C','Distant grain'),('#A2A2A2','Secondary ink'),('#F0817B','Voice accent')]
    for i,(c,label) in enumerate(colors):
        x=70+i*172;s+=rect(x,167,150,92,c,12,'#555555',.5)+text(x,287,label,12,'#F2F2F1',550)+text(x,308,c,11,'#A2A2A2',mono=True)
    s+=text(70,381,'PRESENCE STATES',12,'#F0817B',650,1.7,mono=True)
    states=[('READY','still'),('LISTENING','input energy'),('THINKING','gather inward'),('SPEAKING','output energy'),('MUTED','still + subdued'),('RECONNECTING','broken field')]
    for i,(name,note) in enumerate(states):
        x=64+(i%3)*486;y=419+(i//3)*302
        s+=rect(x,y,452,278,'#242424',22,'#3B3B3B',.7)
        n=[290,560,390,600,150,250][i]
        s+=cloud(x+226,y+121,105,75,n,seed=i+88,scale=.9,accent='#D4D4D4' if i!=4 else '#8C8C8C')
        if i==5:
            s+=rect(x+217,y+28,18,188,'#242424')
        if i in (1,3):s+=waveform(x+171,y+124,110,'particle',True)
        s+=text(x+27,y+235,name,12,'#F0817B' if i in (1,3) else '#F2F2F1',650,1.3,mono=True)
        s+=text(x+426,y+235,note,12,'#A2A2A2',anchor='end')
    s+=text(70,1073,'MOTION RULE',11,'#F0817B',650,1.5,mono=True)+text(70,1104,'12 frequency bands shape local density and drift; Reduce Motion holds the field still; state always has a text label.',15,'#A2A2A2')
    return s+'</svg>'

p=OUT/'drillbit-particle-design-language.svg';p.write_text(system_board());print(p,p.stat().st_size)
