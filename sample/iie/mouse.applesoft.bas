1 REM The mouse card from BASIC, as the AppleMouse II's manual shows it: PR#4 then
2 REM PRINT CHR$(1) turns the mouse on, and IN#4 then INPUT reads X, Y and the button.
3 REM Click the display to give it your mouse (Escape lets go); press a key to stop.
10 HOME
20 PRINT "MOUSE CARD IN SLOT 4"
30 PRINT "CLICK THE DISPLAY, THEN MOVE THE MOUSE"
40 PRINT "AND PRESS ITS BUTTON. A KEY STOPS."
50 PR# 4: PRINT CHR$ (1): PR# 0
60 VTAB 22: HTAB 1
70 IN# 4: INPUT "";X,Y,B: IN# 0
80 VTAB 8: HTAB 1
90 PRINT "X = ";X;"    ": PRINT "Y = ";Y;"    "
100 B$ = "UP": IF ABS (B) = 1 THEN B$ = "HELD"
110 IF ABS (B) = 2 THEN B$ = "PRESSED"
120 IF ABS (B) = 3 THEN B$ = "RELEASED"
130 PRINT "BUTTON = ";B$;"        "
140 IF B > 0 THEN 60
150 GET K$: PR# 4: PRINT CHR$ (0): PR# 0
160 VTAB 20: PRINT "MOUSE OFF."
