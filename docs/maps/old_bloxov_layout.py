import math
S=2.4; M=350; PAD=20; LEG=270
W=int(M*S)+PAD*2+LEG; H=int(M*S)+PAD*2+40
o=[]
def p(v): return PAD+v*S
def rect(x,y,w,h,fill,stroke="#333",sw=1.2,rx=0,dash=None,rot=0):
    d=f' stroke-dasharray="{dash}"' if dash else ''
    r=f' transform="rotate({rot} {p(x+w/2):.1f} {p(y+h/2):.1f})"' if rot else ''
    o.append(f'<rect x="{p(x):.1f}" y="{p(y):.1f}" width="{w*S:.1f}" height="{h*S:.1f}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}{r}/>')
def text(x,y,t,size=10,weight="normal",fill="#111",anchor="middle"):
    lines=t.split("\n")
    for i,l in enumerate(lines):
        o.append(f'<text x="{p(x):.1f}" y="{p(y)+i*(size+2)-(len(lines)-1)*(size+2)/2+size/3:.1f}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}" font-family="Arial,sans-serif">{l}</text>')
def road(pts,w=9,col="#9a9a9a"):
    d=" ".join(f"{p(x):.1f},{p(y):.1f}" for x,y in pts)
    o.append(f'<polyline points="{d}" fill="none" stroke="{col}" stroke-width="{w*S:.1f}" stroke-linejoin="round" stroke-linecap="round"/>')
def circ(x,y,r,fill,stroke="#333"):
    o.append(f'<circle cx="{p(x):.1f}" cy="{p(y):.1f}" r="{r*S:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="1"/>')
LOOT={"cabin":"#a07850","rich":"#f2c84b","police":"#7fa7d9","best":"#c0563f","mid":"#c9c1b3","med":"#f08a8a","food":"#9bd17e","gear":"#b99be0","guns":"#8a8a8a","fuel":"#f0a95a","farm":"#c9a36b"}
def bld(x,y,w,h,label,kind="mid",size=9,rot=0,bold=False):
    rect(x,y,w,h,LOOT[kind],rot=rot); text(x+w/2,y+h/2,label,size,"bold" if bold else "normal")

o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="#fff"/>')
rect(0,0,M,M,"#cfe8c0",sw=2)
# ---- ground: woods + creek
def trees(lst):
    for (x,y,r) in lst: circ(x,y,r,"#8fc27a","#6a9a58")
trees([(20,240,9),(42,258,11),(24,288,10),(58,300,12),(30,322,9),(85,270,10),(72,332,9),(102,312,8),(110,250,7),(124,332,8)])   # SW woods
trees([(280,120,9),(300,130,11),(322,118,9),(338,140,8),(288,150,10),(312,158,11),(334,176,9),(268,142,7),(300,180,8)])           # east woods (farm <-> old houses)
o.append(f'<path d="M{p(0)},{p(212)} C{p(60)},{p(250)} {p(40)},{p(300)} {p(110)},{p(350)}" fill="none" stroke="#7fb3e0" stroke-width="{5*S}"/>')
# ---- railway (y=210) + sidings
RY=210
o.append(f'<line x1="{p(0)}" y1="{p(RY)}" x2="{p(350)}" y2="{p(RY)}" stroke="#6b4f3a" stroke-width="{4*S}" stroke-dasharray="3,2"/>')
o.append(f'<polyline points="{p(232)},{p(RY)} {p(248)},{p(220)} {p(290)},{p(220)}" fill="none" stroke="#6b4f3a" stroke-width="{3*S}"/>')
o.append(f'<polyline points="{p(238)},{p(RY)} {p(254)},{p(228)} {p(290)},{p(228)}" fill="none" stroke="#6b4f3a" stroke-width="{3*S}"/>')
# ---- roads
road([(0,82),(30,80),(62,86),(100,98),(135,96),(168,104),(200,104)])            # Main Street
road([(200,104),(235,92),(265,72),(292,42),(318,0)],8)                           # County road to farm + north exit
road([(62,86),(48,58),(58,30),(95,18),(130,22)],6)                               # Hill Rd
road([(112,100),(118,70),(122,40),(138,8)],6)                                     # Mill Lane
road([(60,88),(52,130),(64,170),(105,196),(150,214),(196,240),(236,270),(290,300),(350,306)],8)   # Old Road -> highway
road([(186,104),(194,150),(214,186)],6)                                          # Station Rd
road([(236,270),(290,258),(350,252)],6)                                          # East Lane
road([(196,240),(180,300),(160,348)],6)                                          # South Lane
# ---- town
rect(8,8,190,180,"none",stroke="#b0442c",sw=1.5,dash="7,4")
text(14,16,"TOWN",11,"bold","#b0442c",anchor="start")
rect(88,108,36,30,"#e8e2d4",stroke="#777")
circ(106,123,3.2,"#a9cbe8")
for (x,y) in [(92,112),(116,112),(92,132),(116,132)]: rect(x,y,4,3,"#7fae6a",stroke="#555",sw=.8)
for (x,y) in [(97,113),(103,133),(110,113)]: rect(x,y,4,2.4,"#c4a36f",stroke="#555",sw=.8)
rect(90,121,6,3,"#8888c8",stroke="#333",sw=.8); rect(117,125,6,3,"#c88888",stroke="#333",sw=.8)
rect(105,129,3,3,"#999",stroke="#333",sw=.8)
text(106,104,"TOWN SQUARE",8,"bold","#555")
bld(82,142,50,18,"TOWN HALL\n+ bunker","best",9,bold=True)
bld(128,110,16,16,"BANK","rich",8,bold=True)
bld(128,128,16,12,"offices","mid",8)
bld(70,128,15,13,"offices","mid",8)
bld(70,70,16,12,"GUN\nSTORE","guns",8,bold=True)
bld(90,72,15,12,"PHARM-\nACY","med",8,bold=True)
bld(128,60,24,20,"GROCERY","food",8,bold=True); rect(154,62,14,18,"#dcdcdc",stroke="#aaa"); text(161,71,"lot",7)
bld(36,68,12,10,"shop","mid",7); bld(50,70,14,10,"shop","mid",7)
bld(66,108,11,9,"","mid")
bld(150,112,26,22,"POLICE\nSTATION","police",8,bold=True)
bld(15,120,30,24,"SCHOOL","gear",9,bold=True); rect(15,148,30,18,"#a8d58f",stroke="#5a8a44"); text(30,157,"field",7)
for (x,y,w,h) in [(30,22,16,13),(68,36,15,12),(75,4,16,11),(100,32,15,12),(28,42,13,12)]:
    bld(x,y,w,h,"big\nhouse","rich",7)
text(56,52,"HILLSIDE",8,"bold","#7a5a00")
# ---- houses between town and farm (top)
for (x,y) in [(214,30),(224,54),(206,72)]: bld(x,y,12,10,"","mid")
# ---- farm
rect(245,8,98,92,"#e8d9a0",stroke="#9a8440"); text(300,18,"FARM",10,"bold","#6b5a20")
bld(256,26,24,18,"barn","farm",8); circ(290,32,4,"#bbb"); bld(306,26,16,12,"farm-\nhouse","mid",7)
bld(256,62,18,12,"shed","farm",7)
for i in range(5): rect(286,50+i*9,52,6,"#d7c27a",stroke="#b8a050",sw=.6)
# ---- train station + depot
bld(200,190,38,14,"TRAIN STATION","mid",8,bold=True)
rect(196,205,50,2.5,"#d8d8d8",stroke="#999")
bld(262,232,30,18,"DEPOT","mid",8,bold=True)
for (x,y) in [(150,208),(270,218),(176,208)]: rect(x,y,10,4,"#a0522d",stroke="#333",sw=.8)
rect(38,RY-4,10,8,"#bfa27a",stroke="#6b4f3a")
# ---- old houses (SE) + gas station
for (x,y) in [(206,258),(248,284),(316,238),(330,268),(304,282),(176,276),(166,318),(214,316)]: bld(x,y,12,10,"","mid")
text(292,224,"",8)
text(268,302,"OLD HOUSES",10,"bold")
bld(298,320,28,14,"GAS STATION","fuel",8,bold=True); rect(296,336,34,6,"#dcdcdc",stroke="#aaa")
bld(276,320,16,12,"diner","food",7); bld(332,322,14,14,"garage","mid",7)
# ---- woods cabins
for (x,y) in [(90,288),(36,304),(306,166)]: bld(x,y,13,10,"cabin","cabin",7)
# ---- labels on top
text(18,74,"Main St",8,"bold","#444",anchor="start")
text(55,222,"WOODS",10,"bold","#3e6b2f"); text(305,145,"WOODS",10,"bold","#3e6b2f")
text(12,226,"creek",8,fill="#2f6a9a",anchor="start")
text(338,204,"railway",8,"bold","#6b4f3a",anchor="end")
# ---- extracts / spawns
def ex(x,y): circ(x,y,4.6,"#2e9e4a","#fff"); text(x,y,"E",10,"bold","#fff")
ex(318,5); text(312,6,"Farm road",8,"bold","#1d6b31",anchor="end")
ex(344,306); text(344,296,"Highway",8,"bold","#1d6b31",anchor="end")
ex(8,340); text(16,340,"Creek trail",8,"bold","#1d6b31",anchor="start")
for (x,y) in [(6,40),(6,180),(100,344),(230,344),(344,120),(344,70),(178,6),(250,152)]:
    o.append(f'<polygon points="{p(x)},{p(y)-7} {p(x)+7},{p(y)+6} {p(x)-7},{p(y)+6}" fill="#2a6fd6" stroke="#fff" stroke-width="1.5"/>')
rect(5,355,50,2,"#000",stroke="none"); text(30,361,"50 m",9)
# ---- legend
lx=PAD+M*S+22; y=PAD+10
o.append(f'<text x="{lx}" y="{y}" font-size="16" font-weight="bold" font-family="Arial,sans-serif">Bloxov Battlegrounds (draft 5)</text>'); y+=18
o.append(f'<text x="{lx}" y="{y}" font-size="11" fill="#555" font-family="Arial,sans-serif">350 x 350 m, north up. Colour = loot type</text>'); y+=18
def leg(col,label,shape="rect"):
    global y
    if shape=="rect": o.append(f'<rect x="{lx}" y="{y}" width="18" height="14" fill="{col}" stroke="#555"/>')
    elif shape=="circle": o.append(f'<circle cx="{lx+9}" cy="{y+7}" r="8" fill="{col}"/>')
    elif shape=="rail": o.append(f'<rect x="{lx}" y="{y+5}" width="18" height="5" fill="{col}"/>')
    else: o.append(f'<polygon points="{lx+9},{y} {lx+17},{y+14} {lx+1},{y+14}" fill="{col}"/>')
    o.append(f'<text x="{lx+26}" y="{y+11}" font-size="11" font-family="Arial,sans-serif">{label}</text>'); y+=21
for k,l in [("best","Town hall: mid upstairs, best in bunker"),("rich","Expensive: big houses, bank"),("police","Armor, pistols: police"),
            ("guns","Guns, gun parts: gun store"),("med","Meds: pharmacy"),("food","Food: grocery, diner"),
            ("gear","Backpacks, gear: school"),("mid","Mid: shops, offices, houses, station"),("fuel","Gas station"),("farm","Farm"),("cabin","Woods cabins (3)")]:
    leg(LOOT[k],l)
y+=4; leg("#2e9e4a","Extract (2 of 3 open)","circle"); leg("#2a6fd6","Player spawn (8)","tri")
leg("#6b4f3a","Railway (boxcars = cover)","rail"); leg("#8fc27a","Woods","circle")
y+=8
for l in ["Town square cover: fountain, planters,","market stalls, parked cars, statue.","Town = dashed red outline."]:
    o.append(f'<text x="{lx}" y="{y}" font-size="11" fill="#444" font-family="Arial,sans-serif">{l}</text>'); y+=15
o.append('</svg>')
open("old_bloxov_layout.svg","w").write("\n".join(o))

