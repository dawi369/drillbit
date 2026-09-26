"""Original deterministic fixtures: 12 band-centre tones and a logarithmic sweep."""
import math, wave, struct
from pathlib import Path
RATE=48000
EDGES=[70*(9000/70)**(i/12) for i in range(13)]
OUT=Path(__file__).resolve().parents[1]/'assets/audio'
def save(name, samples):
    with wave.open(str(OUT/name),'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed'))
        f.writeframes(b''.join(struct.pack('<h',round(max(-1,min(1,x))*32767)) for x in samples))
def scan():
    for lo,hi in zip(EDGES,EDGES[1:]):
        frequency=math.sqrt(lo*hi)
        for n in range(RATE):
            t=n/RATE
            env=min(1,t/.025,max(0,(.8-t)/.06)) if t<.8 else 0
            yield .2*env*math.sin(2*math.pi*frequency*t)
def sweep():
    duration=12
    k=math.log(9000/70)/duration
    for n in range(RATE*duration):
        t=n/RATE
        env=min(1,t/.08,(duration-t)/.08)
        yield .18*env*math.sin(2*math.pi*70*(math.exp(k*t)-1)/k)
save('band-scan.wav',scan())
save('sweep.wav',sweep())
print('Generated band-scan.wav and sweep.wav at 48 kHz mono.')
