import re,sys,glob,os
pat=re.compile(r'\*\*((?:QO|Q|E|L|BF|D)\d+(?:\.\d+)?)\b')
for lab in sorted(glob.glob('src/labs/*.md')):
    sol='src/solutions/'+os.path.basename(lab)
    li=set(pat.findall(open(lab).read()))
    si=set(pat.findall(open(sol).read())) if os.path.exists(sol) else set()
    miss=sorted(li-si, key=lambda s:(re.sub(r'\d','',s),[int(x) for x in re.findall(r'\d+',s)]))
    txt=open(lab).read(); stxt=open(sol).read() if os.path.exists(sol) else ''
    unb_l=txt.count('\n:::')%2; unb_s=stxt.count('\n:::')%2
    print(f"{os.path.basename(lab):32s} labs:{len(li):3d} sol:{len(si):3d} missing:{len(miss):3d} fences_odd:{unb_l}{unb_s}  {' '.join(miss[:12])}")
