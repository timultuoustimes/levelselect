import Foundation

/// Trimmed copies of the real exports of Tim's Fire Emblem Engage sheet (09-17).
enum EngageSheetFixtures {
    static let units = ##"""
Unit,Pic,HP,Str,Mag,Dex,Spd,Def,Res,Lck,Bld,Total,Personal Skill,Description,Gender,HP Cap,Str Cap,Mag Cap,Dex Cap,Spd Cap,Def Cap,Res Cap,Lck Cap,Bld Cap
Alcryst,,65,30,10,40,45,30,20,15,10,265,Get Behind Me!,"When an ally within 2 spaces is attacked, grants Str+3 to unit for 1 turn.",Male,,1,-1,3,,1,-2,-1,
Alear (F),,60,35,20,45,50,40,25,25,5,305,Divinely Inspiring,Adjacent allies deal +3 damage and take 1 less damage.,Female,,1,,1,1,,,,
Alear (M),,60,35,20,45,50,40,25,25,5,305,Divinely Inspiring,Adjacent allies deal +3 damage and take 1 less damage.,Male,,1,,1,1,,,,
Alfred,,65,40,5,35,40,40,20,40,10,295,Self-Improver,"If unit uses Wait without attack or using items, grants Str+2 for 1 turn.",Male,,2,-1,1,,2,-2,-1,
Amber,,65,45,0,25,30,35,5,35,15,255,Aspiring Hero,"If no other units are within 1 space of unit or foe, grants Hit+20 at a cost of Avo-10 during combat.",Female,,2,-1,-1,-1,1,-1,1,
Anna,,55,15,50,50,50,20,35,45,5,325,Make a Killing,May obtain 500G when unit defeats a foe. Trigger %=Lck.,Female,,,1,1,1,-2,-1,1,
Boucheron,,85,20,0,50,45,35,20,15,20,290,Moved to Tears,"When an ally joins a chain attack in this unit's combat, unit deals +2 damage.",Male,,1,,2,2,-2,,-2,
Bunet,,65,30,10,40,35,45,25,40,10,300,Seconds?,"On eating a packed lunch, unit may obtain another of the same item. Trigger %=Lck.",Male,,1,-3,1,,2,-1,1,
Celine,,50,35,25,30,45,30,40,50,5,310,Gentle Flower,Recovery items used by allies withing 2 spaces heal +50% HP.,Female,,-2,2,-2,1,-3,1,3,
Chloe,,75,25,35,40,55,30,25,25,5,315,Fairy-Tale Folk,"If a male and a femal ally are adjacent within 2 spaces, unit deals +2 damage during combat.",Female,,-2,1,,3,-1,,,
Citrinne,,45,10,40,25,30,20,40,25,5,240,Generosity,"When this unit uses a healing item, adjacent allies also recover the same amount of HP.",Female,,-1,3,,-1,-2,2,,
Clanne,,40,35,10,40,50,30,25,20,5,255,Verdant Faith,"If unit is adjacent to the Divine Dragon, grants Hit+10 during combat to both of them.",Male,,1,-1,2,2,-2,-1,,
Diamant,,75,30,15,20,40,40,25,20,15,280,Fair Fight,"If unit initiates combat, grants Hit+15 to unit and foe if foe is able to counterattack.",Male,,2,-1,-1,,2,-1,,
Etie,,45,40,0,25,35,25,30,25,5,230,Energized,"When unit recovers HP using an item, grants Str+2 for 1 turn.",Female,,2,-2,2,,,-1,-1,
Fogado,,60,30,25,30,55,30,35,25,10,300,Charmer,"During combat with a foe who was also unit's most recent opponent, inflicts Crit-10 on that foe.",Male,,-1,-1,,3,-1,1,,
Framme,,55,30,25,35,55,25,30,25,0,280,Crimson Cheer,"If unit is adjacent to the Divine Dragon, grants Avo+10 during combat to both of them.",Female,,,1,-1,2,-1,-1,1,
Goldmary,,65,30,5,25,25,55,25,25,5,260,Disarming Sigh,"If foe is male, inflits Hit-20 on that foe during combat.",Female,,1,-3,,,2,-1,2,
Hortensia,,40,20,20,35,50,25,55,50,0,295,Big Personality,"When unit uses a healing staff, grants range +1",Female,,-2,,,1,-3,3,2,
Ivy,,55,25,30,25,40,30,35,15,10,265,Single-Minded,"During combat with a foe who was also unit's most recent opponent, grants Hit+20.",Female,,,2,-2,,2,2,-3,
Jade,,55,35,25,35,30,40,30,20,10,280,Meditation,"If unit uses Wait without attacking or using items, grants Res+2 for 1 turn.",Female,,1,-1,,,2,,-1,
Jean,,50,20,20,35,40,25,20,25,5,240,Expertise,Grants unit enhanced stat growth when leveling up.,Male,,,2,-1,-1,,,1,
Kagetsu,,60,30,15,50,50,40,25,40,10,320,Blinding Flash,"If unit initiates combat, inflicts Avo-10 on foe during combat.",Male,,-1,-1,2,2,,-2,1,
Lapis,,55,25,20,35,55,35,30,25,5,285,Share Spoils,"If there is an ally with in 1 space, grants Hit/Avo+10 at a cost of Crit-10 to unit.",Female,,-2,-2,2,3,,,,
Lindon,,65,25,25,25,40,25,40,15,10,270,Weapon Insight,"If unit is equipped with a weapon of lower level than foe's, grants Crit+20 during combat.",Male,,,2,-1,,-2,2,,
Louis,,75,40,0,25,25,50,20,25,15,275,Admiration,"If two female allies are adjacent within 2 spaces, this unit takes 2 less damage during combat.",Male,,1,,-1,-2,3,-2,1,
Mauvier,,70,35,40,40,35,50,45,15,15,345,Contemplative,"If unit uses Wait without attacking or using items, grants Def +2 for 1 turn.",Male,,1,2,1,-2,1,1,-2,
Merrin,,55,25,25,40,50,30,30,25,10,290,Knightly Escort,"When 2 or more female allies are within 2 spaces, grants Hit/Avo+5 to unit and those allies.",Female,,-1,-1,1,2,-1,,1,
Pandreo,,60,5,30,45,45,15,55,30,15,300,Party Animal,Grants a bonus to Hit and Avo equal to 3x the number of allies and foes within 2 spaces.,Male,,-3,2,,-1,-2,3,2,
Panette,,75,45,10,40,25,30,15,20,15,275,Blood Fury,"If unit's HP is not at max after combat, grants Crit+10 as long as unit's HP stays below max.",Female,,3,-1,,,,-1,,
Rosado,,75,45,25,40,45,30,30,20,5,315,Stunning Smile,"If foe is male, inflicts Avo-20 on that foe during combat.",Male,,3,-2,1,,1,-2,,
Saphir,,80,35,0,25,30,30,5,20,10,235,Will to Win,"If unit's HP is 50% or less at start of cmbat, grants Hit/Avo+20 during combat.",Female,,2,-2,,1,1,-2,,
Seadall,,55,25,15,25,50,25,25,35,10,265,Curious Dance,"At the start of turn, allies within 2 spaces of unit recover 10% of their max HP.",Male,,,-2,-1,2,,,2,
Timerra,,55,25,25,45,45,30,30,30,10,295,Racket of Solm,Inflicts Crit-5 on foes within 3 spaces.,Female,,-1,-1,3,,2,-3,1,
Vander,,60,25,10,25,35,35,20,10,5,225,Alabaster Duty,"If unit is adjacent to the Divine Dragon, grants Crit+5 during combat to both of them.",Male,,1,-1,1,-2,3,-2,,
Veyle,,40,25,45,35,30,25,35,20,0,255,Fell Protection,Adjacent allies deal +1 damage and take 3 less damage.,Female,,,3,,-1,,3,-2,
Yunaka,,50,35,25,40,45,15,45,25,5,285,Trained to Kill,"While unit occupies terrain that provides an Avo bonus, grants Crit+15.",Female,,-1,,1,2,-2,2,-1,
Zelkov,,65,35,15,40,35,35,15,25,10,275,Not Quite,"If foe initiates combat, inflicts Hit-10 on that foe during combat.",Male,,,-1,2,,,-1,1,
"""##

    static let teamBuilder = ##"""
,Name,Personal Skill,Class Skill,Type,Inherited Skill 1,Inherited Skill 2,HP,Str,Mag,Dex,Spd,Def,Res,Lck,Bld,Growth,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,Class,Description,Description,Proficiency,Description,Description,,,,,,,,,,Max,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,Emblem Ring,,,,Cost,Cost,,,,,,,,,,W/Bond,U HP,U Str,U Mag,U Dex,U Spd,U Def,U Res,U Lck,U Bld,C HP,C Str,C Mag,C Dex,C Spd,C Def,C Res,C Lck,C Bld,U HP,U Str,U Mag,U Dex,U Spd,U Def,U Res,U Lck,U Bld,C HP,C Str,C Mag,C Dex,C Spd,C Def,C Res,C Lck,C Bld,Bond HP,Bond Str,Bond Mag,Bond Dex,Bond Spd,Bond Def,Bond Res,Bond Lck,Bond Bld,Bond Total
,Alear (F),Divinely Inspiring,,Dragon,Starsphere,Name,85,60,35,70,75,65,50,45,25,510,60,35,20,45,50,40,25,25,5,10,10,0,10,10,10,10,5,5,,1,,1,1,,,,,68,41,25,36,43,35,25,35,13,7,,,,,3,,,5,15
,Dragon Child,Adjacent allies deal +3 damage and take 1 less damage.,,Sword B,Grants unit enhanced stat growth when leveling up. [Adds +15% to final growth rates.],Description,68,42,25,37,44,35,25,35,13,324,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,Leif,,,,"1500, Tiki 1",Requirements,75,42,25,37,44,38,25,35,18,339,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,Clanne,Verdant Faith,,Mystical,Name,Name,40,35,35,45,50,30,50,25,5,315,40,35,10,40,50,30,25,20,5,0,0,25,5,0,0,25,5,0,,1,-1,2,2,-2,-1,,,43,26,40,28,30,20,40,24,11,,3,,4,4,,,,,11
,Mage,"If unit is adjacent to the Divine Dragon, grants Hit+10 during combat to both of them.",,Tome B,Description,Description,43,27,39,30,32,18,39,24,11,263,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
"""##

    static let skills = ##"""
Emblem,Bond,Name,Type,SP,Description
Marth,1,Perceptive,Sync Skill (Can Inherit),250,"If the unit initiates combat, grants Avo+15 during combat. Avo increases with high Spd. [+1 Avoid for every 4 Speed.]"
Marth,1,Avoid +10,Inheritable Skill,500,Grants Avo+10.
Marth,1,Divine Speed,Engage Skill,—,"Unit performs an extra attack at 50% damage in combat. [Covert] If extra attack hits, poisons foe. [Dragon] Unit recovers HP equal to damage dealt by extra attack."
Marth,1,Lodestar Rush,Engage Attack,—,Use to launch 7 consecutive sword attacks at 30% damage. Adjacent foe only. [Dragon] +2 attacks. [Backup] +1 attack. [Mystical] Damage based on Mag.
Marth,1,Rapier,Engage Weapon,—,"Sword wielded by Emblem Marth. Effective: Cavalry, Armored."
Marth,2,Sword Agility 1,Inheritable Skill,500,Grants Avo+10 at a cost of Crit-10 when using a sword.
Sigurd,1,Canter,Sync Skill (Can Inherit),1000,Unit can move 2 spaces after acting.
Sigurd,1,Hit +10,Inheritable Skill,500,Grants Hit+10.
Sigurd,1,Gallop,Engage Skill,—,Grants Mov+5. [Dragon] Grants another Mov+1. [Cavalry] Grants another Mov+2. [Covert] Unit does not pay extra movement cost on any terrain.
Sigurd,1,Override,Engage Attack,—,Use to attack and move through a line of adjacent foes. Sword/lance only.
Sigurd,,,,,[Dragon] +20% damage.
Sigurd,,,,,[Armored] 10% chance of breaking target.
"""##

}
