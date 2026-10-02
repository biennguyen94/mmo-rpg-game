#!/usr/bin/env python3
"""Parse Item.txt -> items_raw.json (REFERENCE thuần, version s5+, verified:false).
Dòng item: Index ItemSlot Skill X Y Serial Option Drop "Name" <tab padding> ...giá trị.
Padding tab giữa tên và ItemLvl KHÔNG cố định => lấy các trường KHÔNG rỗng sau tên.
"""
import json, re, sys
GROUPS = {0:'Sword',1:'Axe',2:'Scepter',3:'Spear',4:'Bow/Crossbow',5:'Staff',6:'Shield',7:'Helm',
          8:'Armor',9:'Pants',10:'Gloves',11:'Boots',12:'Wing/Orb/Seed',13:'Pet/Ring/Pendant',
          14:'Potion/Jewel/Quest',15:'Scroll'}
CLS = ['DW','DK','ELF','MG','DL','SUM']
WEAPON = ['ItemLvl','DmgMin','DmgMax','Speed','Durability','MagicDur','MagicPwr','ReqLvl','Str','Agi','Ene','Vit','Command','Type']
DEFENSE = ['ItemLvl','Def','DefRate','Durability','ReqLvl','Str','Agi','Ene','Vit','Command','Type']
LAYOUT = {g:WEAPON for g in range(0,6)}
LAYOUT.update({g:DEFENSE for g in range(6,12)})
LAYOUT[12] = ['Lvl','Def','Durability','ReqLvl','Ene','Str','Agi','Comm','Zen']
LAYOUT[13] = ['Lvl','Durability','Ice','Poison','Light','Fire','Earth','Wind','Water','Type']
LAYOUT[14] = ['Valor','ItemLvl']
LAYOUT[15] = ['Lvl','ReqLvl','Energy','Zen']
HAS_CLASS = set(range(0,14)) | {12,15}
def parse(path):
    raw = open(path,'rb').read().decode('utf-8', errors='replace')
    out, group, warn = [], None, []
    for n,line in enumerate(raw.splitlines(),1):
        s=line.strip()
        if not s or s.startswith('//'): continue
        if s=='end': group=None; continue
        if re.fullmatch(r'\d+',s) and group is None: group=int(s); continue
        if group is None: continue
        m=re.match(r'^([^"]*)"([^"]*)"(.*)$', line)
        if not m: warn.append((n,'no name',s[:60])); continue
        head=[x.strip() for x in m.group(1).split('\t') if x.strip()!='']
        tail=m.group(3).split()
        # bỏ comment cuối dòng nếu có
        tail=[x for x in tail if not x.startswith('//')]
        if len(head)<8: warn.append((n,'head<8',s[:60])); continue
        rec={'group':group,'index':int(head[0]),'slotMU':int(head[1]),'skill':int(head[2]),
             'x':int(head[3]),'y':int(head[4]),'name':m.group(2),'line':n}
        cols=LAYOUT[group]; need=len(cols)+(6 if group in HAS_CLASS else 0)
        try: vals=[int(v) for v in tail]
        except ValueError: warn.append((n,'non-int',tail)); continue
        if len(vals)<need: warn.append((n,f'tail {len(vals)}<{need}',m.group(2))); 
        for c,v in zip(cols,vals): rec[c]=v
        if group in HAS_CLASS and len(vals)>=need:
            cl=vals[len(cols):len(cols)+6]; rec['classTier']=dict(zip(CLS,cl))
        out.append(rec)
    return out,warn
if __name__=='__main__':
    items,warn=parse(sys.argv[1])
    json.dump({'sourceType':'REFERENCE','version':'s5+','verified':False,'source':'Item.txt','items':items},
              open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False,indent=1)
    from collections import Counter
    print('items',len(items),Counter(i['group'] for i in items)); print('warnings',len(warn))
    for w in warn[:30]: print(w)
