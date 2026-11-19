// The cars of Redline Rush that the garage designer page (garage_concepts.html) does not have, in its own spec language:
// the four cheaper garage cars and the traffic sedan and hatchback. tools/garage/export.js puts this into the page's code just
// before the interiors are given out, so CARS, INTERIORS and every helper of the page are in scope here.
// Each is drawn after one real car of its class (the first name in `cues`), at its real size.

/* ============ PULSE — starter hot hatch ============ */
CARS.push({
  id:'pulse',name:'Pulse Hatch',short:'Pulse',group:'Garage',tag:'Starter · Free',paint:'#2f62b0',metallic:false,
  blurb:'A five-door hot hatch on big wheels: quick to turn in, happy to rev, and practical with it.',
  cues:'Hyundai i30 N · Ford Focus ST · Honda Civic Type R',
  notes:['A modern five-door hatch at the real thing\'s size: 4.34 m long on a 2.65 m wheelbase, sat low on 19-inch wheels.','A big black mesh grille between slim swept headlamps, with a red pinstripe along the front lip and the side skirts.','A roof spoiler over the tailgate glass, twin oval exhausts and a triangle brake lamp in the diffuser for the chase cam.'],
  stats:[['Accel',5.6,11],['Top',52,81],['Grip',9.5,14],['Brake',9,13]],
  body:{L:4.335,
    top:[[0,.64],[.04,.72],[.12,.77],[.4,.8],[.9,.845],[1.22,.885],[1.36,.91],[2.2,.952],[3.2,.988],[3.9,1.012],[4.18,1.018],[4.29,1.0],[4.325,.97],[4.335,.93]],
    width:[[0,.8],[.1,.856],[.4,.884],[.92,.894],[1.5,.886],[2.6,.878],[3.57,.893],[4.05,.884],[4.25,.868],[4.335,.845]],
    clr:[[0,.3],[.25,.2],[.92,.15],[3.57,.15],[4.05,.22],[4.335,.33]],
    nU:[[0,4.4],[.92,5],[1.7,4.4],[3.57,4.8],[4.335,5]],nL:3,tuck:.9,tumble:.05,hc:[[0,.62],[.92,.7],[1.8,.6],[3.57,.68],[4.335,.64]],
    capF:.1,capR:.065,capTopK:.4,capBotK:.5,archGap:.035,archDrop:.025,flare:[.012,.014]},
  wheels:{xF:.92,xR:3.57,rF:.324,rR:.324,rimF:.2413,rimR:.2413,twF:.235,twR:.235,zF:.78,zR:.785,steer:.22,
    rimStyle:{style:'split',n:5,w0:.024,w1:.03,sepH:.03,sepR:.12,conc:.04}},
  cabin:{pts:[[1.38,0],[1.66,1.08],[1.9,1.26],[2.15,1.375],[2.5,1.435],[2.9,1.447],[3.3,1.43],[3.62,1.39],[3.9,1.24],[4.12,1.04],[4.2,0]],
    wsTop:2.15,rwTop:3.62,bx:2.62,bw:.075,cx:[3.84,3.58],inset:.03,tumble:.12,n:4.6,pillar:.055,pillarR:.15,
    mats:{roof:'paint',a:'paint',c:'paint',b:'trim'}},
  accentMat:'nRed',
  mats:{rim:{c:'#2a2d31',m:1,r:.3,cc:.8},caliper:{c:'#c8102e',m:0,r:.35,cc:1},nRed:{c:'#d0121b',r:.35,cc:1}},
  mask:(p,n,api)=>{const [x,y]=p;
    const lip=X(band(y,.205,.225),.42-x), skirt=X(band(y,.2,.217),sideN(n),x-1.25,3.25-x);
    return [-1,U(X(.215-y,x-.4,4.1-x),X(.3-y,.42-x),X(.36-y,x-4.08)),U(lip,skirt)];},
  seams:[seamX(1.48,.22,.92,-.08),seamX(2.6,.22,.95,0),seamX(3.45,.36,.98,.2),seamTop(.2,.66,.7),seamZ(.66,.2,1.36,.7),seamY(.58,4.08,4.4,.75),seamZ(.8,4.08,4.4,.6)],
  extras(k){const L=k.L;
    k.F(pg([[-.44,.4],[.44,.4],[.52,.55],[.43,.67],[-.43,.67],[-.52,.55]],[.03,.03,.04,.02,.02,.04]),'grille',0,false);
    k.F(pg([[.46,.665],[.8,.685],[.86,.775],[.53,.745]],[.01,.02,.025,.012]),'hl');
    k.F(pg([[.49,.722],[.8,.738],[.83,.756],[.51,.738]],.004),'drl',1);
    k.F(el(.6,.7,.026),'proj',1);k.F(el(.7,.708,.025),'proj',1);
    k.F(pg([[.62,.27],[.78,.29],[.8,.43],[.66,.42]],.015),'grille');
    k.F(rr(.73,.45,.09,.03,.01),'amberLens');
    k.F(rr(0,.31,.5,.11,.008),'plate',0,false);
    k.R(pg([[.4,.82],[.8,.83],[.85,.915],[.47,.92]],[.012,.02,.02,.012]),'tl');
    k.R(pg([[.46,.862],[.79,.865],[.82,.884],[.48,.882]],.005),'tlGlow',1);
    k.R(rr(.78,.842,.05,.018,.005),'amberLens',1);
    k.R(rr(0,.315,1.1,.1,.02),'trim',0,false);
    k.R(pg([[0,.335],[.04,.285],[-.04,.285]],.004),'tlGlow',1,false);
    k.R(rr(0,.66,.5,.11,.008),'plate',0,false);
    for(const z of [-.56,.56])k.exhaust(z,.29,.045,.1);
    k.diffuser([-.3,-.15,.15,.3],.38,.04,'trim');
    {const x=3.6,y=k.roofY(x);k.add(extrude('paint',[[0,0],[.19,-.03],[.24,.012],[.04,.03]],-.6,.6,false).xf(M3.I(),[x,y-.012,0]));}
    k.handle(2.1);k.handle(3.15);
    k.mirrorPart(1.66,.99,'paint','trim',[.085,.06,.115]);
    k.wipers();
  }
});

/* ============ VECTOR GS — rally-bred sport sedan ============ */
CARS.push({
  id:'vector',name:'Vector GS',short:'Vector GS',group:'Garage',tag:'Shop · $600',paint:'#c11a22',metallic:false,
  blurb:'A turbo four-door built for gravel stages: all grip, a big wing and an angry face.',
  cues:'Mitsubishi Lancer Evolution X · Subaru WRX STI · VW Jetta GLI',
  notes:['A rally saloon at the real size: 4.5 m long on a 2.65 m wheelbase, with flared arches over 18-inch wheels.','A huge inverted-trapezoid "jet fighter" grille, angular headlamps, two big bonnet vents and vents in the front wings.','A tall rear wing on two posts, clear round-element tail lamps and twin tips on the right.'],
  stats:[['Accel',6,11],['Top',54,81],['Grip',10.5,14],['Brake',9.5,13]],
  body:{L:4.495,
    top:[[0,.72],[.04,.78],[.12,.805],[.6,.832],[1.2,.875],[1.62,.915],[1.76,.93],[2.6,.965],[3.6,.995],[4.1,1.025],[4.38,1.045],[4.47,1.036],[4.495,1.0]],
    width:[[0,.8],[.12,.868],[.5,.898],[.98,.906],[1.6,.894],[2.6,.89],[3.63,.906],[4.2,.89],[4.495,.84]],
    clr:[[0,.32],[.25,.2],[.98,.145],[3.63,.145],[4.2,.22],[4.495,.34]],
    nU:[[0,4],[.98,5],[1.8,4.2],[3.63,4.4],[4.495,4]],nL:3,tuck:.9,tumble:.05,hc:[[0,.62],[.98,.72],[1.8,.6],[3.63,.68],[4.495,.62]],
    capF:.07,capR:.07,capTopK:.4,capBotK:.5,archGap:.04,archDrop:.03,flare:[.02,.022]},
  wheels:{xF:.98,xR:3.63,rF:.327,rR:.327,rimF:.2286,rimR:.2286,twF:.245,twR:.245,zF:.773,zR:.773,steer:.22,
    rimStyle:{style:'spoke',n:10,w0:.02,w1:.026,conc:.035}},
  cabin:{pts:[[1.72,0],[2.0,1.1],[2.25,1.3],[2.5,1.42],[2.85,1.47],[3.25,1.475],[3.55,1.44],[3.8,1.33],[4.02,1.14],[4.15,0]],
    wsTop:2.48,rwTop:3.58,bx:2.95,bw:.08,cx:[3.9,3.6],inset:.03,tumble:.13,n:4.4,pillar:.055,
    mats:{roof:'paint',a:'paint',c:'paint',b:'trim'}},
  mats:{rim:{c:'#1f2124',m:.8,r:.3,cc:.8},caliper:{c:'#c9ccd1',m:.6,r:.3,cc:.6}},
  mask:(p,n,api)=>{const [x,y]=p;
    return [-1,U(X(.22-y,x-.4,4.2-x),X(.3-y,.4-x),X(.37-y,x-4.18)),-1];},
  seams:[seamX(1.8,.24,.94,-.1),seamX(2.93,.24,.97,0),seamX(3.62,.38,.99,.25),seamTop(.18,.64,.74),seamZ(.64,.18,1.7,.74),seamTop(4.12,.72,.9),seamZ(.72,4.12,4.48,.9)],
  extras(k){const L=k.L;
    k.F(pg([[-.36,.34],[.36,.34],[.6,.69],[-.6,.69]],[.03,.03,.02,.02]),'grille',0,false);
    k.F(rr(0,.7,1.22,.014,.006),'gloss',0,false);
    k.F(pg([[.6,.665],[.87,.685],[.89,.765],[.65,.745]],[.01,.02,.02,.01]),'hl');
    k.F(pg([[.65,.73],[.86,.74],[.87,.753],[.66,.743]],.004),'drl',1);
    k.F(el(.72,.7,.032),'proj',1);k.F(el(.81,.705,.026),'warm',1);
    k.F(pg([[.66,.3],[.84,.32],[.86,.46],[.72,.44]],.015),'grille');
    k.F(rr(0,.25,.5,.11,.008),'plate',0,false);
    k.T(pg([[.45,.16],[.82,.18],[.82,.36],[.45,.34]],.03),'vent');
    k.T(rr(1.0,0,.22,.2,.03),'vent',0,false);
    k.S(pg([[1.28,.64],[1.48,.66],[1.46,.75],[1.3,.73]],.012),'vent');
    k.R(pg([[.45,.84],[.86,.85],[.88,.94],[.5,.935]],[.012,.02,.02,.012]),'tl');
    k.R(el(.62,.893,.028),'tlGlow',1);k.R(el(.76,.896,.028),'tlGlow',1);
    k.R(rr(.84,.885,.03,.04,.008),'amberLens',1);
    k.R(rr(0,.33,1.2,.1,.02),'trim',0,false);
    k.R(rr(0,.62,.5,.11,.008),'plate',0,false);
    for(const z of [-.55,-.43])k.exhaust(z,.31,.045,.12);
    k.diffuser([-.25,0,.25],.4,.045,'trim');
    // the wing: two posts on the boot lid and a tall aerofoil between them
    {const xs=4.22,y=k.topY(xs);
      for(const z of [-.55,.55])k.add(k.rbox('paint',[xs+.02,y+.09,z],[.05,.09,.012],.3));
      k.wing('paint',xs-.1,y+.17,.72,.26,.1,.08);}
    k.handle(2.42);k.handle(3.42);
    k.mirrorPart(1.95,.99,'paint');
    k.wipers();
  }
});

/* ============ HORNET — city pocket rocket ============ */
CARS.push({
  id:'hornet',name:'Hornet Compact',short:'Hornet',group:'Garage',tag:'Shop · $800',paint:'#e8b10f',metallic:false,
  blurb:'A tiny retro city car with a loud exhaust: nips through gaps nothing else fits.',
  cues:'Abarth 595 · Mini Cooper S · Suzuki Swift Sport',
  notes:['A rounded three-door bubble at the real size: 3.66 m long on a 2.3 m wheelbase, on 17-inch wheels.','Round headlamps low in the bumper with oval running lamps above, a chrome moustache and a big lower intake.','A black roof and spoiler, a stripe low down the doors and four exhaust tips under the tail.'],
  stats:[['Accel',5.4,11],['Top',49,81],['Grip',10,14],['Brake',9.5,13]],
  body:{L:3.66,
    top:[[0,.64],[.04,.71],[.15,.77],[.4,.82],[.7,.867],[.92,.91],[1.02,.93],[2.0,.965],[2.9,.978],[3.38,.975],[3.56,.958],[3.63,.93],[3.66,.885]],
    width:[[0,.7],[.1,.76],[.35,.795],[.7,.805],[1.5,.8],[2.5,.795],[3.0,.805],[3.45,.785],[3.66,.74]],
    clr:[[0,.3],[.25,.2],[.7,.15],[3.0,.15],[3.45,.22],[3.66,.32]],
    nU:[[0,3.8],[.7,4.2],[1.6,3.8],[3.0,4.2],[3.66,4.4]],nL:2.8,tuck:.9,tumble:.06,hc:[[0,.58],[.7,.66],[1.6,.58],[3.0,.64],[3.66,.6]],capF:.16,capR:.09,capTopK:.5,capBotK:.5,archGap:.035,archDrop:.02,flare:[.016,.016]},
  wheels:{xF:.7,xR:3.0,rF:.298,rR:.298,rimF:.2159,rimR:.2159,twF:.205,twR:.205,zF:.705,zR:.7,steer:.24,
    rimStyle:{style:'spoke',n:5,w0:.034,w1:.044,conc:.03,twist:.18}},
  cabin:{pts:[[.98,0],[1.2,1.1],[1.38,1.3],[1.58,1.415],[1.9,1.475],[2.3,1.487],[2.7,1.475],[3.02,1.44],[3.28,1.35],[3.46,1.2],[3.56,1.02],[3.6,0]],
    wsTop:1.58,rwTop:3.06,bx:2.62,bw:.07,cx:[3.26,3.02],inset:.035,tumble:.16,n:4,pillar:.055,pillarR:.15,
    mats:{roof:'trim',a:'paint',c:'paint',b:'trim'}},
  cabinTrimMat:'gloss',accentMat:'matte',
  mats:{rim:{c:'#16171a',m:.7,r:.3,cc:.9},caliper:{c:'#c41a1a',m:0,r:.35,cc:1}},
  mask:(p,n,api)=>{const [x,y]=p;
    const stripe=X(band(y,.33,.37),sideN(n),x-1.05,2.6-x);
    return [-1,U(X(.235-y,x-.35,3.4-x),X(.31-y,.34-x),X(.35-y,x-3.38)),stripe];},
  seams:[seamX(1.06,.24,.93,-.12),seamX(2.48,.24,.96,.1),seamZ(.6,.08,.98,.62),seamTop(.08,.6,.62),seamY(.62,3.35,3.7,.7),seamZ(.68,3.35,3.7,.62)],
  extras(k){const L=k.L;
    k.F(el(.5,.6,.075),'hlChrome',1);k.F(el(.5,.6,.056),'proj',2);
    k.F(el(.47,.735,.056,.02),'drl',1);
    k.F(rr(0,.7,.46,.028,.012),'chrome',0,false);
    k.F(el(0,.71,.035,.026),'satin',1,false);
    k.F(pg([[-.36,.27],[.36,.27],[.43,.44],[-.43,.44]],[.04,.04,.05,.05]),'grille',0,false);
    k.F(rr(.62,.36,.08,.06,.02),'grille');
    k.F(rr(0,.5,.46,.1,.008),'plate',0,false);
    k.R(rr(.54,.8,.13,.21,.05),'tl');
    k.R(rr(.54,.8,.1,.18,.04),'tlGlow',1);k.R(rr(.54,.8,.06,.12,.025),'paint',2);
    k.R(rr(.54,.74,.05,.02,.006),'amberLens',3);
    k.R(rr(0,.31,1.0,.09,.02),'trim',0,false);
    k.R(rr(0,.66,.46,.1,.008),'plate',0,false);
    for(const z of [-.42,-.32,.32,.42])k.exhaust(z,.27,.026,.08);
    {const x=3.04,y=k.roofY(x);k.add(extrude('gloss',[[0,0],[.15,-.035],[.19,0],[.03,.026]],-.55,.55,false).xf(M3.I(),[x,y-.012,0]));}
    k.handle(2.2,'chrome',.1);
    k.mirrorPart(1.26,1.0,'paint','trim',[.07,.055,.1]);
    // (shorter wipers than the page's own: the windscreen is narrow)
    {const x=k.api.cab.x0+.07,y=Math.max(k.roofY(x-.035),k.roofY(x+.035))+.014;
      for(const zc of [-.25,.15])k.add(k.rbox('trim',[x,y,zc],[.012,.008,.2],.25,M3.ry(.06)));}
  }
});

/* ============ COMET — rear-drive sports coupe ============ */
CARS.push({
  id:'comet',name:'Comet Coupe',short:'Comet',group:'Garage',tag:'Shop · $1,000',paint:'#123f8c',metallic:true,
  blurb:'A light front-engined, rear-drive two-door: balanced, playful and easy to slide.',
  cues:'Toyota GR86 · Subaru BRZ · Mazda MX-5 RF',
  notes:['A low 2+2 coupe at the real size: 4.27 m long and 1.31 m tall on a 2.58 m wheelbase, with 18-inch wheels.','A long bonnet between raised wing tops, a wide mesh grille low in the bumper and vents behind the front wheels.','A short fastback deck with a ducktail, wide tail lamps and a big round exhaust at each corner.'],
  stats:[['Accel',5.8,11],['Top',55,81],['Grip',10.5,14],['Brake',10,13]],
  body:{L:4.265,
    top:[[0,.6],[.04,.67],[.15,.705],[.6,.735],[1.2,.775],[1.58,.81],[1.72,.83],[2.6,.85],[3.4,.885],[3.9,.93],[4.1,.958],[4.22,.968],[4.255,.955],[4.265,.92]],
    width:[[0,.76],[.12,.84],[.5,.874],[.86,.884],[1.5,.864],[2.4,.858],[3.0,.874],[3.435,.886],[3.9,.874],[4.265,.82]],
    clr:[[0,.26],[.3,.16],[.86,.12],[3.435,.12],[3.95,.2],[4.265,.3]],
    nU:[[0,4],[.86,5.2],[1.6,4.2],[3.435,4.8],[4.265,4]],nL:2.8,tuck:.9,tumble:.06,hc:[[0,.6],[.86,.74],[1.7,.6],[3.0,.62],[3.435,.72],[4.265,.62]],
    capF:.09,capR:.065,capTopK:.4,capBotK:.5,archGap:.03,archDrop:.02,flare:[.014,.024],riseBoost:[.028,.016]},
  wheels:{xF:.86,xR:3.435,rF:.315,rR:.315,rimF:.2286,rimR:.2286,twF:.215,twR:.215,zF:.76,zR:.775,steer:.22,
    rimStyle:{style:'split',n:5,w0:.022,w1:.028,sepH:.028,sepR:.14,conc:.045}},
  cabin:{pts:[[1.68,0],[1.98,1.0],[2.22,1.17],[2.45,1.265],[2.75,1.305],[3.05,1.3],[3.3,1.25],[3.55,1.14],[3.8,1.0],[3.98,0]],
    wsTop:2.45,rwTop:3.15,bx:null,cx:[3.45,3.12],inset:.025,tumble:.17,n:4,pillar:.06,
    mats:{roof:'paint',a:'paint',c:'paint',b:'paint'}},
  mats:{rim:{c:'#3a3d42',m:1,r:.22,cc:.8},caliper:{c:'#c41a1a',m:0,r:.35,cc:1}},
  mask:(p,n,api)=>{const [x,y]=p;
    return [-1,U(X(.2-y,x-.35,3.95-x),X(.28-y,.45-x),X(.34-y,x-3.95)),-1];},
  seams:[seamX(1.75,.2,.84,-.1),seamX(2.97,.22,.86,.12),seamTop(.16,.6,.66),seamZ(.6,.16,1.62,.66),seamTop(3.98,.68,.86),seamZ(.68,3.98,4.25,.86)],
  extras(k){const L=k.L;
    k.F(pg([[-.48,.24],[.48,.24],[.57,.36],[.5,.5],[-.5,.5],[-.57,.36]],[.03,.03,.04,.03,.03,.04]),'grille',0,false);
    k.F(pg([[.5,.58],[.84,.6],[.865,.665],[.56,.65]],[.01,.02,.02,.01]),'hl');
    k.F(pg([[.53,.623],[.835,.637],[.85,.653],[.545,.639]],.004),'drl',1);
    k.F(pg([[.8,.595],[.84,.605],[.85,.645],[.82,.64]],.004),'drl',1);
    k.F(el(.64,.607,.024),'proj',1);k.F(el(.73,.613,.022),'proj',1);
    k.F(pg([[.64,.28],[.82,.3],[.84,.44],[.68,.43]],.015),'grille');
    k.F(rr(0,.22,.5,.11,.008),'plate',0,false);
    k.S(pg([[1.22,.54],[1.38,.56],[1.38,.63],[1.24,.61]],.008),'vent');
    k.R(pg([[.42,.8],[.84,.815],[.865,.885],[.46,.875]],[.012,.02,.02,.012]),'tl');
    k.R(pg([[.46,.835],[.83,.842],[.85,.858],[.48,.852]],.004),'tlGlow',1);
    k.R(rr(.83,.84,.018,.05,.005),'tlGlow',1);
    k.R(rr(0,.3,1.24,.09,.02),'trim',0,false);
    k.R(rr(0,.58,.5,.11,.008),'plate',0,false);
    for(const z of [-.58,.58])k.exhaust(z,.27,.045,.1);
    k.diffuser([-.32,-.12,.12,.32],.42,.045,'trim');
    {const y=k.topY(4.16);k.add(extrude('paint',[[0,0],[.1,0],[.13,.028],[.02,.01]],-.64,.64,false).xf(M3.I(),[4.12,y-.006,0]));}
    k.handle(2.6,'trim',.12);
    k.mirrorPart(1.98,.86,'paint','trim',[.075,.05,.1]);
    k.wipers();
  }
});

/* ============ TRAFFIC — mid-size sedan ============ */
CARS.push({
  id:'sedan',name:'Traffic Sedan',short:'Sedan',group:'Traffic',tag:'Traffic · Every lane',paint:'#8c939b',metallic:true,
  blurb:'The family four-door everyone drives. Also the base of the police cruiser.',
  cues:'Toyota Camry · Honda Accord · Hyundai Sonata',
  notes:['A mid-size sedan at the real size: 4.89 m long on a 2.83 m wheelbase, on 17-inch alloys.','A slim upper grille with a chrome bar, a huge slatted lower grille and sharp swept headlamps.','Chrome round the windows and across the boot lid, and wide tail lamps.'],
  body:{L:4.885,
    top:[[0,.68],[.04,.76],[.15,.795],[.7,.832],[1.4,.9],[1.82,.945],[1.95,.96],[3,.99],[4.1,1.02],[4.5,1.04],[4.8,1.05],[4.87,1.04],[4.885,1.0]],
    width:[[0,.82],[.15,.9],[.5,.914],[1.02,.92],[2.4,.914],[3.845,.92],[4.4,.905],[4.885,.85]],
    clr:[[0,.3],[.35,.19],[1.02,.15],[3.845,.15],[4.5,.23],[4.885,.36]],
    nU:[[0,4.2],[1.02,4.6],[2.4,4.2],[3.845,4.6],[4.885,4.8]],nL:3,tuck:.9,tumble:.05,hc:.6,capF:.11,capR:.075,capTopK:.4,capBotK:.5,archGap:.04,archDrop:.03},
  wheels:{xF:1.02,xR:3.845,rF:.334,rR:.334,rimF:.2159,rimR:.2159,twF:.215,twR:.215,zF:.8,zR:.8,steer:.2,
    rimStyle:{style:'spoke',n:5,w0:.036,w1:.046,conc:.03,twist:.25}},
  cabin:{pts:[[1.88,0],[2.18,1.08],[2.42,1.26],[2.66,1.38],[3.0,1.435],[3.4,1.44],[3.75,1.41],[4.0,1.32],[4.22,1.16],[4.4,0]],
    wsTop:2.66,rwTop:3.78,bx:3.15,bw:.08,cx:[4.15,3.85],inset:.03,tumble:.14,n:4.5,pillar:.055,chrome:true,
    mats:{roof:'paint',a:'paint',c:'paint',b:'trim'}},
  cabinAccentMat:'chrome',
  mats:{rim:{c:'#b9bec4',m:1,r:.25,cc:.6},caliper:{c:'#3b3d41',m:.4,r:.55}},
  mask:(p,n,api)=>{const [x,y]=p;
    return [-1,U(X(.22-y,x-.4,4.5-x),X(.3-y,.4-x),X(.38-y,x-4.5)),-1];},
  seams:[seamX(1.96,.24,.96,-.08),seamX(3.12,.24,.99,0),seamX(4.0,.4,1.02,.28),seamTop(.2,.7,.78),seamZ(.68,.2,1.85,.78),seamTop(4.42,.78,.95),seamZ(.76,4.42,4.86,.95)],
  extras(k){const L=k.L;
    k.F(rr(0,.665,.6,.065,.02),'grille',0,false);
    k.F(rr(0,.705,.64,.012,.006),'chrome',0,false);
    k.F(pg([[-.62,.3],[.62,.3],[.68,.52],[-.68,.52]],[.04,.04,.05,.05]),'slats',0,false);
    k.F(pg([[.5,.63],[.86,.655],[.885,.745],[.56,.715]],[.012,.02,.025,.012]),'hl');
    k.F(pg([[.53,.69],[.85,.71],[.87,.73],[.55,.708]],.004),'drl',1);
    k.F(el(.66,.67,.03),'proj',1);k.F(el(.77,.68,.028),'proj',1);
    k.F(rr(.76,.4,.1,.03,.01),'amberLens');
    k.F(rr(0,.4,.5,.11,.008),'plate',0,false);
    k.R(pg([[.42,.83],[.86,.84],[.88,.92],[.48,.925]],[.012,.02,.02,.012]),'tl');
    k.R(pg([[.48,.875],[.85,.875],[.865,.895],[.5,.895]],.005),'tlGlow',1);
    k.R(rr(.82,.85,.05,.02,.005),'amberLens',1);
    k.R(rr(0,.83,.72,.018,.008),'chrome',0,false);
    k.R(rr(0,.62,.5,.11,.008),'plate',0,false);
    k.exhaust(-.55,.33,.035,.08);
    k.handle(2.75);k.handle(3.85);
    k.mirrorPart(2.1,1.02,'paint');
    k.wipers();
  }
});

/* ============ TRAFFIC — small hatchback ============ */
CARS.push({
  id:'hatch',name:'Traffic Hatch',short:'Hatch',group:'Traffic',tag:'Traffic · Every lane',paint:'#a8323a',metallic:false,
  blurb:'A small five-door supermini: light, slow and everywhere.',
  cues:'VW Polo · Toyota Yaris · Renault Clio',
  notes:['A supermini at the real size: 4.05 m long on a 2.55 m wheelbase, on 16-inch wheels.','A narrow black grille band runs between the headlamps over a trapezoid lower intake.','Wedge-shaped tail lamps run into the tailgate.'],
  body:{L:4.053,
    top:[[0,.68],[.04,.75],[.15,.79],[.55,.825],[1.1,.88],[1.38,.915],[1.5,.935],[2.4,.965],[3.4,.99],[3.85,1.0],[3.98,.996],[4.035,.975],[4.053,.94]],
    width:[[0,.76],[.12,.83],[.45,.86],[.82,.868],[1.6,.864],[2.6,.86],[3.372,.868],[3.8,.855],[4.053,.8]],
    clr:[[0,.3],[.3,.2],[.82,.15],[3.372,.15],[3.8,.22],[4.053,.34]],
    nU:[[0,4.3],[.82,4.8],[2,4.3],[3.372,4.8],[4.053,5]],nL:3,tuck:.9,tumble:.05,hc:.58,capF:.1,capR:.06,capTopK:.4,capBotK:.5,archGap:.035,archDrop:.025},
  wheels:{xF:.82,xR:3.372,rF:.31,rR:.31,rimF:.2032,rimR:.2032,twF:.195,twR:.195,zF:.762,zR:.76,steer:.2,
    rimStyle:{style:'disc',n:10,w0:.016,w1:.026,conc:.02,twist:.6}},
  cabin:{pts:[[1.42,0],[1.7,1.08],[1.94,1.26],[2.16,1.38],[2.55,1.445],[2.95,1.455],[3.3,1.44],[3.6,1.38],[3.82,1.2],[3.95,1.0],[4.0,0]],
    wsTop:2.16,rwTop:3.6,bx:2.6,bw:.075,cx:[3.72,3.5],inset:.03,tumble:.12,n:4.8,pillar:.055,pillarR:.15,
    mats:{roof:'paint',a:'paint',c:'paint',b:'trim'}},
  mats:{rim:{c:'#b0b5bb',m:.8,r:.3,cc:.5},caliper:{c:'#3b3d41',m:.4,r:.55}},
  mask:(p,n,api)=>{const [x,y]=p;
    return [-1,U(X(.215-y,x-.35,3.8-x),X(.3-y,.35-x),X(.35-y,x-3.8)),-1];},
  seams:[seamX(1.5,.22,.94,-.08),seamX(2.58,.22,.97,0),seamX(3.32,.36,.99,.2),seamTop(.2,.66,.72),seamZ(.66,.2,1.42,.72),seamY(.62,3.8,4.1,.72),seamZ(.74,3.8,4.1,.6)],
  extras(k){const L=k.L;
    k.F(rr(0,.68,.72,.07,.02),'grille',0,false);
    k.F(rr(0,.643,1.3,.01,.005),'chrome',0,false);
    k.F(pg([[.36,.64],[.8,.66],[.82,.74],[.4,.725]],[.012,.02,.02,.012]),'hl');
    k.F(pg([[.4,.675],[.79,.687],[.81,.703],[.42,.695]],.004),'drl',1);
    k.F(el(.54,.68,.028),'proj',1);k.F(el(.66,.685,.026),'warm',1);
    k.F(pg([[-.42,.3],[.42,.3],[.48,.46],[-.48,.46]],[.03,.03,.04,.04]),'grille',0,false);
    k.F(el(.66,.36,.035),'hlChrome');k.F(el(.66,.36,.025),'warm',1);
    k.F(rr(0,.48,.5,.11,.008),'plate',0,false);
    k.R(pg([[.38,.8],[.82,.81],[.84,.89],[.45,.905]],[.012,.02,.02,.012]),'tl');
    k.R(pg([[.45,.845],[.81,.85],[.825,.868],[.47,.865]],.005),'tlGlow',1);
    k.R(rr(.78,.825,.06,.018,.005),'amberLens',1);
    k.R(rr(0,.31,1.1,.08,.02),'trim',0,false);
    k.R(rr(0,.7,.5,.11,.008),'plate',0,false);
    k.exhaust(.45,.31,.03,.08);
    k.handle(2.15);k.handle(3.15);
    k.mirrorPart(1.6,1.0,'paint','trim',[.08,.06,.11]);
    k.wipers();
  }
});

// ---- their interiors
Object.assign(LIB,{
  nBlue:{c:'#1f4fa0',r:.4,cc:.4},
  nSuede:{c:'#232427',r:.95},
  nRedS:{c:'#b3141c',r:.4,cc:.3},
});
Object.assign(INTERIORS,{
  pulse:{hx:2.56,floor:.24,cush:.5,dd:.56,wheel:{style:'sport',r:.185,t:.019},markMat:'nBlue',seat:'sport',insertMat:'iPulseS',
    cluster:'dials2',screen:'tablet',shifter:'ball',trimMat:'iCarbon',rear:{hx:3.42,cush:.5,back:.3},shell:'#232427',shelf:'#111214',tint:.48,
    mats:{iPulseS:{c:'#2a2b2f',r:.95,pat:9},iGauge:{c:'#0a0a0a',e:[1.4,1.9,2.6],pat:7}},
    note:'Interior: sport seats in suede with quilted centres, carbon-look trim, two round dials, a floating touchscreen, a short-throw 6-speed and a sport wheel with a blue centre mark.'},
  vector:{hx:2.9,floor:.22,cush:.47,dd:.58,wheel:{style:'sport',r:.185,t:.02},markMat:'nRedS',paddles:true,seat:'bucket',insertMat:'iVecR',
    cluster:'dials2',bezel:true,shifter:'auto',trimMat:'iCarbon',rear:{hx:3.72,cush:.48,back:.3},shell:'#1c1d20',shelf:'#0e0f11',tint:.5,
    mats:{iVecR:{c:'#1e1f22',r:.85,pat:11},iGauge:{c:'#0a0a0a',e:[2.4,.6,.3],pat:7}},
    note:'Interior: black bucket seats with pleated centres, carbon-look trim, red-lit dials in chrome rings, a twin-clutch selector and paddles behind a three-spoke wheel.'},
  hornet:{hx:2.12,floor:.27,cush:.56,dd:.48,wheel:{style:'flat',r:.18,t:.02},markMat:'nRedS',seat:'sport',insertMat:'iHornS',dashMat:'iHornD',
    cluster:'dials2',screen:'tablet',shifter:'ball',trimMat:'iChrome',rear:{hx:2.86,cush:.52,back:.27},doorEnd:2.45,shell:'#1d1e21',shelf:'#0f1012',tint:.48,
    mats:{iHornS:{c:'#26272a',r:.9,pat:9},iHornD:{c:'#e8b10f',r:.32,cc:.7},iGauge:{c:'#0a0a0a',e:[2.4,1.9,1.2],pat:7}},
    note:'Interior: a dashboard panel in the body colour, quilted sport seats, round dials, a small touchscreen and a flat-bottomed wheel with a red centre mark.'},
  comet:{hx:2.85,floor:.18,cush:.37,dd:.55,tilt:20,wheel:{style:'sport',r:.18,t:.019},markMat:'nRedS',seat:'bucket',seatMat:'iCometS',insertMat:'iCometI',
    cluster:'screen',screen:'land',shifter:'ball',trimMat:'iSoft',rear:{hx:3.42,cush:.37,back:.24},shell:'#1b1c1f',shelf:'#0d0e10',tint:.48,
    mats:{iCometS:{c:'#1c1c1e',r:.6,cc:.15},iCometI:{c:'#3a3b3f',r:.95},iScreen:{c:'#05070a',e:[.7,1.3,2.4],pat:8}},
    note:'Interior: low bucket seats with grey suede centres, a digital cluster, a small landscape screen, a stubby 6-speed and a small sport wheel.'},
  sedan:{hx:3.05,floor:.24,cush:.5,dd:.62,wheel:{style:'sport',r:.19,t:.019},seat:'comfort',seatMat:'iSedS',insertMat:'iSedI',
    cluster:'dials2',screen:'tablet',shifter:'auto',trimMat:'iWood',rear:{hx:3.95,cush:.52,back:.31},shell:'#3a3631',shelf:'#1a1816',tint:.5,
    mats:{iSedS:{c:'#8f8576',r:.7,cc:.1},iSedI:{c:'#7d7465',r:.85,pat:11},iDash:{c:'#1e1d1c',r:.62,cc:.1}},
    note:'Interior: beige leather seats front and rear, wood trim, a tablet touchscreen and an automatic selector.'},
  hatch:{hx:2.58,floor:.25,cush:.52,dd:.55,wheel:{style:'basic',r:.185,t:.019},seat:'basic',seatMat:'iHatS',insertMat:'iHatI',
    cluster:'dials2',screen:'tablet',shifter:'ball',rear:{hx:3.42,cush:.52,back:.3},shell:'#2f3033',shelf:'#151618',tint:.5,
    mats:{iHatS:{c:'#2e3034',r:.9},iHatI:{c:'#3a3c41',r:.95,pat:10}},
    note:'Interior: patterned cloth seats, a simple dash with two dials and a touchscreen, and a manual gear lever.'},
});
