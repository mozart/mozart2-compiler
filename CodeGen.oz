%%%
%%% Author:
%%%   Leif Kornstaedt <kornstae@ps.uni-sb.de>
%%%
%%% Copyright:
%%%   Leif Kornstaedt, 1997
%%%
%%% Last change:
%%%   $Date$ by $Author$
%%%   $Revision$
%%%
%%% This file is part of Mozart, an implementation of Oz 3:
%%%    $MOZARTURL$
%%%
%%% See the file "LICENSE" or
%%%    $LICENSEURL$
%%% for information on usage and redistribution
%%% of this file, and for a DISCLAIMER OF ALL
%%% WARRANTIES.
%%%

%%
%% General Notes:
%%
%% meth codeGen(CS ?VInstrs)
%%    CS is an instance of the CodeStore class.  It encapsulates the
%%    internal state of the code generator (generation of virtual
%%    registers as well as compiler switches) and stores the produced
%%    code.  Its methods annotate this code, perform register assignment,
%%    and emit the code.
%%

%\define DEBUG_DEFS

local
   proc {CodeGenList Nodes CS VHd VTl}
      case Nodes of Node|Noder then VInter in
         {Node codeGen(CS VHd VInter)}
         {CodeGenList Noder CS VInter VTl}
      [] nil then
         VHd = VTl
      end
   end

   fun {CoordNoDebug Coord}
      case {Label Coord} of pos then Coord
      else {Adjoin Coord pos}
      end
   end

   proc {StepPoint Coord Comment VHd VTl VInter1 VInter2}
      case {IsStep Coord} then
         VInter2 = nil
         VHd = vStepPoint(_ VInter1 Coord Comment VTl)
      else
         VHd = VInter1
         VInter2 = VTl
      end
   end

   proc {MakeUnify Reg1 Reg2 VHd VTl}
      case Reg1 == Reg2 then
         % If we left it in, it would create unnecessary Reg occurrences.
         VHd = VTl
      else
         VHd = vUnify(_ Reg1 Reg2 VTl)
      end
   end

   proc {MakePermanent Vs ?Regs VHd VTl}
      Regs = {FoldR Vs
              fun {$ V In}
                 case {V getOrigin($)} \= generated then {V reg($)}|In
                 else In
                 end
              end nil}
      case Regs of nil then
         VHd = VTl
      else
         VHd = vMakePermanent(_ Regs VTl)
      end
   end

   proc {Clear Regs VHd VTl}
      case Regs of nil then
         VHd = VTl
      else
         VHd = vClear(_ Regs VTl)
      end
   end

   %%
   %% Instances of PseudoVariableOccurrences are used when in some
   %% code generation context a variable occurrence is required but
   %% only a register index is available (for example, in case of
   %% a late expansion where said register is freshly generated).
   %%

   class PseudoVariableOccurrence
      prop final
      feat reg value coord
      meth init(Reg)
         self.reg = Reg
      end
      meth getCoord($) C = self.coord in
         case {IsDet C} then C else unit end
      end
      meth getVariable($)
         self
      end
      meth isToplevel($)
         false
      end
      meth assignRegToStructure(CS)
         skip
      end
      meth getCodeGenValue($)
         self.value
      end
      meth reg($)
         self.reg
      end
      meth makeEquation(CS VO VHd VTl) Value = self.value in
         case {IsDet Value} then
            case {IsNumber Value} then
               VHd = vEquateNumber(_ Value {VO reg($)} VTl)
            elsecase {IsLiteral Value} then
               VHd = vEquateLiteral(_ Value {VO reg($)} VTl)
            else
               {MakeUnify self.reg {VO reg($)} VHd VTl}
            end
         else
            {MakeUnify self.reg {VO reg($)} VHd VTl}
         end
      end
      meth makeRecordArgument(CS VHd VTl $) Value = self.value in
         VHd = VTl
         case {IsDet Value} then
            case {IsNumber Value} then
               number(Value)
            elsecase {IsLiteral Value} then
               literal(Value)
            else
               value(self.reg)
            end
         else
            value(self.reg)
         end
      end
      meth makeVO(CS VHd VTl ?VO)
         VHd = VTl
         VO = self
      end
   end

   fun {NewPseudoVariableOccurrence CS}
      {New PseudoVariableOccurrence init({CS newReg($)})}
   end

   fun {GetExpansionOcc PrintName Node ErrCoord CS} VO in
      VO = Node.expansionOccs.PrintName
      case VO of undeclared then PVO in
         {CS.reporter error(coord: ErrCoord kind: 'code generation error'
                            msg: 'system variable '#pn(PrintName)#
                                 ' used before its declaration')}
         PVO = {NewPseudoVariableOccurrence CS}
         PVO.coord = ErrCoord
         PVO
      else VO
      end
   end

   proc {MakeMessageArgs ActualArgs CS ?Regs VHd VTl}
      case ActualArgs of Arg|Argr then Reg1 Regr VInter VO in
         {Arg makeVO(CS VHd VInter ?VO)}
         {VO reg(?Reg1)}
         Regs = Reg1|Regr
         {MakeMessageArgs Argr CS ?Regr VInter VTl}
      [] nil then
         Regs = nil
         VHd = VTl
      end
   end

   local
      proc {LoadActualArgs ActualArgs CS VHd VTl ?NewArgs}
         case ActualArgs of Arg|Argr then Value VInter NewArgr in
            {Arg getCodeGenValue(?Value)}
            case {IsDet Value} andthen {IsName Value} then PVO in
               PVO = {NewPseudoVariableOccurrence CS}
               PVO.value = Value
               VHd = vEquateLiteral(_ Value {PVO reg($)} VInter)
               NewArgs = PVO|NewArgr
            else
               VHd = VInter
               NewArgs = Arg|NewArgr
            end
            {LoadActualArgs Argr CS VInter VTl ?NewArgr}
         [] nil then
            VHd = VTl
            NewArgs = nil
         end
      end

      fun {GetRegs VOs}
         case VOs of VO|VOr then {VO reg($)}|{GetRegs VOr}
         [] nil then nil
         end
      end
   in
      proc {MakeApplication Designator Coord ActualArgs CS VHd VTl}
         Value NewActualArgs VInter
      in
         {Designator getCodeGenValue(?Value)}
         {LoadActualArgs ActualArgs CS VHd VInter ?NewActualArgs}
         case {IsDet Value} andthen {IsProcedure Value} then
            {Designator
             codeGenApplication(Designator Coord NewActualArgs CS VInter VTl)}
         elsecase {{Designator getVariable($)} isToplevel($)}
            andthen {Not CS.debugInfoControlSwitch}
         then
            VInter = vGenCall(_ {Designator reg($)}
                              false '' {Length NewActualArgs}
                              {GetRegs NewActualArgs} Coord VTl)
         else
            VInter = vCall(_ {Designator reg($)} {GetRegs NewActualArgs}
                           Coord VTl)
         end
      end
   end

   proc {MakeException Node Literal Coord VOs CS VHd VTl}
      RaiseError Reg VO VArgs VInter
   in
      RaiseError = {GetExpansionOcc '`RaiseError`' Node Coord CS}
      {CS newReg(?Reg)}
      VO = {New PseudoVariableOccurrence init(Reg)}
      VArgs =
      literal(Literal)|number(case Coord of unit then ~1 else Coord.2 end)|
      {Map VOs fun {$ VO} value({VO reg($)}) end}
      VHd = vEquateRecord(_ 'kernel' {Length VArgs} Reg VArgs VInter)
      {MakeApplication RaiseError {CoordNoDebug Coord} [VO] CS VInter VTl}
   end

   fun {GuardNeedsThread VInstr}
      case {IsFree VInstr} then false
      elsecase VInstr of nil then false
      [] vEquateNumber(_ _ _ Cont) then {GuardNeedsThread Cont}
      [] vEquateLiteral(_ _ _ Cont) then {GuardNeedsThread Cont}
      [] vEquateRecord(_ _ _ _ _ Cont) then {GuardNeedsThread Cont}
      [] vUnify(_ _ _ Cont) then {GuardNeedsThread Cont}
      [] vFailure(_ Cont) then {GuardNeedsThread Cont}   %--** emulator bug?
      else true
      end
   end

   fun {GuardIsShallow VInstr}
      case {IsFree VInstr} then true
      elsecase VInstr of nil then true
      [] vEquateNumber(_ _ _ Cont) then {GuardIsShallow Cont}
      [] vEquateLiteral(_ _ _ Cont) then {GuardIsShallow Cont}
      [] vEquateRecord(_ _ _ _ _ Cont) then {GuardIsShallow Cont}
      [] vUnify(_ _ _ Cont) then {GuardIsShallow Cont}
      else false
      end
   end

   class SwitchHashTable
      prop final
      attr
         coord: unit Scalars: nil Records: nil AltNode: unit
         Arbiter: unit WarnedCatchAll: false
      feat Reg cs
      meth init(Coord TestReg TheAltNode TheArbiter CS)
         coord <- Coord
         AltNode <- TheAltNode
         Arbiter <- TheArbiter
         self.Reg = TestReg
         self.cs = CS
      end
      meth addScalar(NumOrLit LocalVars Body)
         Scalars <- NumOrLit#LocalVars#Body|@Scalars
      end
      meth addRecord(Rec Clause)
         Records <- SwitchHashTable, AddRecord(@Records Rec Clause $)
      end
      meth AddRecord(Records Rec Clause $)
         case Records of X|Rr then R1#Clauses = X in
            case R1 == Rec then (Rec#(Clause|Clauses))|Rr
            else X|SwitchHashTable, AddRecord(Rr Rec Clause $)
            end
         [] nil then
            [Rec#[Clause]]
         end
      end

      meth codeGen(VHd VTl)
         CS = self.cs NonvarTests RecordTests AltAddr
      in
         NonvarTests = {FoldL @Scalars
                        case CS.debugInfoVarnamesSwitch then
                           fun {$ In NumOrLit#LocalVars#Body}
                              Regs BodyAddr Cont1 Cont2 in
                              {MakePermanent LocalVars ?Regs BodyAddr Cont1}
                              {CodeGenList Body CS Cont1 Cont2}
                              {Clear Regs Cont2 nil}
                              onScalar(NumOrLit BodyAddr)|In
                           end
                        else
                           fun {$ In NumOrLit#_#Body} BodyAddr in
                              {CodeGenList Body CS BodyAddr nil}
                              onScalar(NumOrLit BodyAddr)|In
                           end
                        end
                        RecordTests}
         RecordTests = {Map @Records
                        fun {$ Rec#Clauses}
                           SwitchHashTable, CodeGenRecord(Rec Clauses $)
                        end}
         {@AltNode codeGenWithArbiterShared(CS @Arbiter AltAddr nil)}
         VHd = vMatch(_ self.Reg AltAddr NonvarTests @coord VTl _)
      end
      meth CodeGenRecord(Rec Clauses ?VHashTableEntry)
         CS = self.cs CondVInstr
      in
         case Clauses of [LocalVars#Subpatterns#_#Body] then
            % Generating unnecessary vShallowGuard instructions precludes
            % making good decisions during register allocation.  If the
            % subpatterns only consist of linear pattern variable occurrences,
            % then we can do without.
            proc {MakeGuard Patterns V1Hd V1Tl V2Hd V2Tl PatternVs}
               % V1Hd-V1Tl stores the vGetVariable instructions;
               % V2Hd-V2Tl stores the instructions to descend into patterns
               case Patterns of Pattern|Rest then
                  V1Inter V2Inter NewPatternVs
               in
                  {Pattern makeGetArg(CS PatternVs V1Hd V1Inter V2Hd V2Inter
                                      ?NewPatternVs)}
                  {MakeGuard Rest V1Inter V1Tl V2Inter V2Tl NewPatternVs}
               [] nil then
                  V1Hd = V1Tl
                  V2Hd = V2Tl
               end
            end
            GetVariablesTl GuardVHd GuardVTl BodyVInstr
         in
            {MakeGuard Subpatterns
             CondVInstr GetVariablesTl GuardVHd GuardVTl nil}
            case CS.debugInfoVarnamesSwitch then Regs Cont1 Cont2 in
               {MakePermanent LocalVars ?Regs BodyVInstr Cont1}
               {CodeGenList Body CS Cont1 Cont2}
               {Clear Regs Cont2 nil}
            else
               {CodeGenList Body CS BodyVInstr nil}
            end
            case {IsFree GuardVHd} then
               % we need no vShallowGuard instruction since the guard
               % cannot fail.
               GetVariablesTl = BodyVInstr
            elsecase {GuardIsShallow GuardVHd} then AltVInstr AllocatesRS in
               GuardVTl = nil
               {@AltNode codeGenWithArbiterShared(CS @Arbiter AltVInstr nil)}
               {CS makeRegSet(?AllocatesRS)}
               {CS enterVs([@Arbiter] AllocatesRS)}
               GetVariablesTl = vShallowGuard(_ GuardVHd BodyVInstr AltVInstr
                                              unit nil AllocatesRS _)
            else AltVInstr in
               GuardVTl = vAsk(_ nil)
               {@AltNode codeGenWithArbiterShared(CS @Arbiter AltVInstr nil)}
               GetVariablesTl = vCreateCond(_ [_#GuardVHd#BodyVInstr]
                                            AltVInstr nil unit nil _)
            end
         else
            proc {MakeGuard Patterns VOs VHd VTl}
               case Patterns of Pattern|Rest then VO|VOr = VOs VInter in
                  {Pattern makeEquation(CS VO VHd VInter)}
                  {MakeGuard Rest VOr VInter VTl}
               [] nil then
                  VHd = VTl
               end
            end
            VOs GetVariablesTl VClauses AltVInstr
         in
            VOs = {Map {Arity Rec}
                   fun {$ _} {NewPseudoVariableOccurrence CS} end}
            {FoldL VOs
             proc {$ VHd VO VTl}
                VHd = vGetVariable(_ {VO reg($)} VTl)
             end CondVInstr GetVariablesTl}
            VClauses =
            {FoldL Clauses
             fun {$ In LocalVars#Subpatterns#Coord#Body}
                GuardVHd GuardVTl GuardVInstr Cont BodyVInstr
             in
                {MakeGuard Subpatterns VOs GuardVHd GuardVTl}
                case {GuardNeedsThread GuardVHd} then
                   GuardVTl = nil
                   GuardVInstr = vThread(_ GuardVHd Coord Cont _)
                else
                   GuardVTl = Cont
                   GuardVInstr = GuardVHd
                end
                Cont = vAsk(_ nil)
                case CS.debugInfoVarnamesSwitch then Regs Cont3 Cont4 in
                   {MakePermanent LocalVars ?Regs BodyVInstr Cont3}
                   {CodeGenList Body CS Cont3 Cont4}
                   {Clear Regs Cont4 nil}
                else
                   {CodeGenList Body CS BodyVInstr nil}
                end
                _#GuardVInstr#BodyVInstr|In
             end nil}
            {@AltNode codeGenWithArbiterShared(CS @Arbiter AltVInstr nil)}
            GetVariablesTl = vCreateCond(_ VClauses AltVInstr nil unit nil _)
         end
         case {IsTuple Rec} then
            VHashTableEntry = onRecord({Label Rec} {Width Rec} CondVInstr)
         else
            VHashTableEntry = onRecord({Label Rec} {Arity Rec} CondVInstr)
         end
      end
   end

   local
      fun {MakeFromPropSub FromProp CS VHd VTl}
         case FromProp of VO|VOr then ArgIn VInter ConsReg X = unit NewArg in
            ArgIn = {MakeFromPropSub VOr CS VHd VInter}
            {CS newReg(?ConsReg)}
            {VO makeRecordArgument(CS X X ?NewArg)}
            VInter = vEquateRecord(_ '|' 2 ConsReg [NewArg ArgIn] VTl)
            value(ConsReg)
         [] nil then
            VHd = VTl
            literal(nil)
         end
      end
   in
      proc {MakeFromProp FromProp CS VHd VTl ?VO} Reg in
         case FromProp of _|_ then
            value(Reg) = {MakeFromPropSub FromProp CS VHd VTl}
         [] nil then
            {CS newReg(?Reg)}
            VHd = vEquateLiteral(_ nil Reg VTl)
         end
         VO = {New PseudoVariableOccurrence init(Reg)}
      end
   end

   local
      fun {MakeAttrFeatSub Xs OOFreeFlag}
         case Xs of X|Xr then
            case X of F#VO then X else X#OOFreeFlag end|
            {MakeAttrFeatSub Xr OOFreeFlag}
         [] nil then
            nil
         end
      end
   in
      proc {MakeAttrFeat Kind AttrFeat ClassObject C CS VHd VTl ?VO}
         OOFreeFlag = {GetExpansionOcc '`ooFreeFlag`' ClassObject C CS}
         Label = {New Core.atomNode init(Kind unit)}
         Args = {MakeAttrFeatSub AttrFeat OOFreeFlag}
         Constr = {New Core.construction init(Label Args false)}
         E1 = Constr.expansionOccs
         E2 = ClassObject.expansionOccs
      in
         E1.'`tuple`' = E2.'`tuple`'
         E1.'`record`' = E2.'`record`'
         E1.'`tellRecordSize`' = E2.'`tellRecordSize`'
         E1.'`^`' = E2.'`^`'
         VO = {NewPseudoVariableOccurrence CS}
         {Constr makeEquation(CS VO VHd VTl)}
      end
   end

   class CodeGenRecord
      meth getCodeGenValue($)
         case {IsDet {@label getCodeGenValue($)}}
            andthen {All @args
                     fun {$ Arg}
                        case Arg of F#_ then {IsDet {F getCodeGenValue($)}}
                        else true
                        end
                     end}
         then @value
         else _
         end
      end
      meth makeEquation(CS VO VHd VTl)
         % Since record patterns may be nested, we need to generate a
         % register index for each subtree that is in turn a construction:
         {ForAll @args
          proc {$ Arg}
             case Arg of _#T then {T assignRegToStructure(CS)}
             else {Arg assignRegToStructure(CS)}
             end
          end}
         % Determine in which way the record may be constructed.
         % (General note: construct it top-down; this is required so that
         % the shallowGuard instruction works.)
         case @isOpen then VInter in
            CodeGenRecord, MakeConstructionOpen(CS VO VHd VInter)
            {self makeEquationDescend(CS VInter VTl)}
         else Label Feats LabelIsDet FeatsAreDet in
            {@label getCodeGenValue(?Label)}
            Feats = {List.mapInd @args
                     fun {$ I Arg}
                        case Arg of F#_ then {F getCodeGenValue($)}
                        else I
                        end
                     end}
            LabelIsDet = {IsDet Label}
            FeatsAreDet = {All Feats IsDet}
            case LabelIsDet andthen FeatsAreDet then VInter in
               CodeGenRecord,
               MakeConstructionBasic(CS VO Label Feats VHd VInter)
               {self makeEquationDescend(CS VInter VTl)}
            elsecase FeatsAreDet then PairList Rec in
               PairList = {List.zip Feats @args
                           fun {$ F Arg}
                              case Arg of _#T then F#T else F#Arg end
                           end}
               try
                  Rec = {List.toRecord someLabel PairList}
               catch failure(...) then C = {@label getCoord($)} in
                  {CS.reporter
                   error(coord: C kind: 'code generation error'
                         msg: 'duplicate feature in record construction')}
                  Rec = {FoldL PairList fun {$ In F#T} {AdjoinAt In F T} end
                         someLabel()}
               end
               case {IsTuple Rec} then VInter in
                  CodeGenRecord, MakeConstructionTuple(CS VO Rec VHd VInter)
                  {self makeEquationDescend(CS VInter VTl)}
               else Args VInter in
                  Args = {Record.toListInd Rec}
                  CodeGenRecord, MakeConstructionRecord(CS VO Args VHd VInter)
                  {self makeEquationDescend(CS VInter VTl)}
               end
            else Args VInter in
               Args = {List.zip Feats @args
                       fun {$ FV Arg} F T in
                          case Arg of X#Y then F = X T = Y else T = Arg end
                          case {IsDet FV} andthen
                             ({IsInt FV} orelse {IsLiteral FV})
                          then FV
                          else F
                          end#T
                       end}
               CodeGenRecord, MakeConstructionRecord(CS VO Args VHd VInter)
               {self makeEquationDescend(CS VInter VTl)}
            end
         end
      end

      meth MakeConstructionBasic(CS VO Label Feats VHd VTl)
         case Feats of nil then   % transform `f()' into `f':
            VHd = vEquateLiteral(_ Label {VO reg($)} VTl)
         else PairList Rec RecordArity VArgs VInter in
            PairList = {List.zip Feats @args
                        fun {$ F Arg}
                           case Arg of _#T then F#T else F#Arg end
                        end}
            try
               Rec = {List.toRecord Label PairList}
            catch failure(...) then C = {@label getCoord($)} in
               {CS.reporter
                error(coord: C kind: 'code generation error'
                      msg: 'duplicate feature in record construction')}
               Rec = {FoldL PairList fun {$ In F#T} {AdjoinAt In F T} end
                      Label()}
            end
            case {IsTuple Rec} then
               RecordArity = {Width Rec}
               VArgs#VInter = {ForThread RecordArity 1 ~1
                               fun {$ In#VTl I} VArg VHd in
                                  {Rec.I makeRecordArgument(CS VHd VTl ?VArg)}
                                  (VArg|In)#VHd
                               end nil#VTl}
            else
               RecordArity = {Arity Rec}
               VArgs#VInter = {FoldR RecordArity
                               fun {$ F In#VTl} VArg VHd in
                                  {Rec.F makeRecordArgument(CS VHd VTl ?VArg)}
                                  (VArg|In)#VHd
                               end nil#VTl}
            end
            VHd = vEquateRecord(_ Label RecordArity {VO reg($)} VArgs VInter)
         end
      end
      meth MakeConstructionOpen(CS VO VHd VTl)
         C CND TellRecordSize Hat WidthReg WidthVO Cont1 Cont2 in
         % translate the construction as:
         %    {`tellRecordSize` Label Width ?VO}
         %    {`^` VO Feat1 Subtree1} ... {`^` VO Featn Subtreen}
         {@label getCoord(?C)}
         CND = {CoordNoDebug C}
         TellRecordSize = {GetExpansionOcc '`tellRecordSize`' self C CS}
         Hat = {GetExpansionOcc '`^`' self C CS}
         {CS newReg(?WidthReg)}
         WidthVO = {New PseudoVariableOccurrence init(WidthReg)}
         VHd = vEquateNumber(_ {Length @args} WidthReg Cont1)
         case {@label isVariableOccurrence($)} then
            {MakeApplication TellRecordSize CND
             [@label WidthVO VO] CS Cont1 Cont2}
         else LabelReg LabelVO LabelValue Inter in
            {CS newReg(?LabelReg)}
            LabelVO = {New PseudoVariableOccurrence init(LabelReg)}
            {@label getCodeGenValue(?LabelValue)}
            Cont1 = vEquateLiteral(_ LabelValue LabelReg Inter)
            {MakeApplication TellRecordSize {CoordNoDebug C}
             [LabelVO WidthVO VO] CS Inter Cont2}
         end
         {List.foldLInd @args
          proc {$ I VHd Arg VTl} VO1 VO2 VInter1 in
             case Arg of F#T then VInter2 in
                {F makeVO(CS VHd VInter2 ?VO1)}
                {T makeVO(CS VInter2 VInter1 ?VO2)}
             else VInter2 in
                VO1 = {NewPseudoVariableOccurrence CS}
                VO1.value = I
                VHd = vEquateNumber(_ I {VO1 reg($)} VInter2)
                {Arg makeVO(CS VInter2 VInter1 ?VO2)}
             end
             {MakeApplication Hat CND [VO VO1 VO2] CS VInter1 VTl}
          end Cont2 VTl}
      end
      meth MakeConstructionTuple(CS VO Rec VHd VTl)
         C BQTuple SubtreesReg SubtreesVO WidthValue WidthReg WidthVO
         Cont1 Cont2
      in
         % translate the construction as:
         %    {`tuple` Label [Subtree1 ... Subtreen] Width ?Reg}
         {@label getCoord(?C)}
         BQTuple = {GetExpansionOcc '`tuple`' self C CS}
         {CS newReg(?SubtreesReg)}
         SubtreesVO = {New PseudoVariableOccurrence init(SubtreesReg)}
         WidthValue = {Width Rec}
         {CS newReg(?WidthReg)}
         WidthVO = {New PseudoVariableOccurrence init(WidthReg)}
         case WidthValue of 0 then
            VHd = vEquateLiteral(_ nil SubtreesReg Cont1)
         else
            fun {MakeList I VHd VTl}
               case I =< WidthValue then
                  ArgIn VInter1 ConsReg VInter2 NewArg
               in
                  ArgIn = {MakeList I + 1 VHd VInter1}
                  {CS newReg(?ConsReg)}
                  {Rec.I makeRecordArgument(CS VInter1 VInter2 ?NewArg)}
                  VInter2 = vEquateRecord(_ '|' 2 ConsReg [NewArg ArgIn] VTl)
                  value(ConsReg)
               else
                  VHd = VTl
                  literal(nil)
               end
            end
            Arg VInter1 VInter2 NewArg
         in
            Arg = {MakeList 2 VHd VInter1}
            {Rec.1 makeRecordArgument(CS VInter1 VInter2 ?NewArg)}
            VInter2 = vEquateRecord(_ '|' 2 SubtreesReg [NewArg Arg] Cont1)
         end
         Cont1 = vEquateNumber(_ WidthValue WidthReg Cont2)
         case {@label isVariableOccurrence($)} then
            {MakeApplication BQTuple {CoordNoDebug C}
             [@label SubtreesVO WidthVO VO] CS Cont2 VTl}
         else LabelReg LabelVO LabelValue Inter in
            {CS newReg(?LabelReg)}
            LabelVO = {New PseudoVariableOccurrence init(LabelReg)}
            {@label getCodeGenValue(?LabelValue)}
            Cont2 = vEquateLiteral(_ LabelValue LabelReg Inter)
            {MakeApplication BQTuple {CoordNoDebug C}
             [LabelVO SubtreesVO WidthVO VO] CS Inter VTl}
         end
      end
      meth MakeConstructionRecord(CS VO Args VHd VTl)
         C BQRecord SubtreesReg SubtreesVO Cont
      in
         % translate the construction as:
         %    {`record` Label [Feat1#Subtree1 ... Featn#Subtreen] ?Reg}
         {@label getCoord(?C)}
         BQRecord = {GetExpansionOcc '`record`' self C CS}
         {CS newReg(?SubtreesReg)}
         SubtreesVO = {New PseudoVariableOccurrence init(SubtreesReg)}
         case Args of (F1#A1)|Argr then   % else it would have been a tuple
            fun {MakePairList Args VHd VTl}
               case Args of F#A|Argr then
                  ArgIn VInter1 PairReg ConsReg PairArg1 PairArg2
                  VInter2 VInter3
               in
                  ArgIn = {MakePairList Argr VHd VInter1}
                  {CS newReg(?PairReg)}
                  {CS newReg(?ConsReg)}
                  PairArg1 = case {IsInt F} then number(F)
                             elsecase {IsLiteral F} then literal(F)
                             else value({F reg($)})
                             end
                  {A makeRecordArgument(CS VInter1 VInter2 ?PairArg2)}
                  VInter2 = vEquateRecord(_ '#' 2 PairReg [PairArg1 PairArg2]
                                          VInter3)
                  VInter3 = vEquateRecord(_ '|' 2 ConsReg
                                          [value(PairReg) ArgIn] VTl)
                  value(ConsReg)
               [] nil then
                  VHd = VTl
                  literal(nil)
               end
            end
            Arg VInter1 PairReg PairArg1 PairArg2 VInter2 VInter3
         in
            Arg = {MakePairList Argr VHd VInter1}
            {CS newReg(?PairReg)}
            PairArg1 = case {IsInt F1} then number(F1)
                       elsecase {IsLiteral F1} then literal(F1)
                       else value({F1 reg($)})
                       end
            {A1 makeRecordArgument(CS VInter1 VInter2 ?PairArg2)}
            VInter2 = vEquateRecord(_ '#' 2 PairReg
                                    [PairArg1 PairArg2] VInter3)
            VInter3 = vEquateRecord(_ '|' 2 SubtreesReg
                                    [value(PairReg) Arg] Cont)
         end
         case {@label isVariableOccurrence($)} then
            {MakeApplication BQRecord {CoordNoDebug C}
             [@label SubtreesVO VO] CS Cont VTl}
         else LabelReg LabelVO LabelValue Inter in
            {CS newReg(?LabelReg)}
            LabelVO = {New PseudoVariableOccurrence init(LabelReg)}
            {@label getCodeGenValue(?LabelValue)}
            Cont = vEquateLiteral(_ LabelValue LabelReg Inter)
            {MakeApplication BQRecord {CoordNoDebug C}
             [LabelVO SubtreesVO VO] CS Inter VTl}
         end
      end
   end

   local
      fun {OzValueToVArg Value CS VHd VTl}
         case {IsNumber Value} then
            VHd = VTl
            number(Value)
         elsecase {IsLiteral Value} then
            VHd = VTl
            literal(Value)
         else Reg in
            {CS newReg(?Reg)}
            {OzValueToVInstr Value Reg CS VHd VTl}
            value(Reg)
         end
      end

      proc {OzValueToVInstr Value Reg CS VHd VTl}
         case {IsNumber Value} then
            VHd = vEquateNumber(_ Value Reg VTl)
         elsecase {IsLiteral Value} then
            VHd = vEquateLiteral(_ Value Reg VTl)
         elsecase {IsTuple Value} then
            fun {MakeArgs I VHd VTl}
               case I =< RecordArity then VArg VInter in
                  VArg = {OzValueToVArg Value.I CS VHd VInter}
                  VArg|{MakeArgs I + 1 VInter VTl}
               else
                  VHd = VTl
                  nil
               end
            end
            RecordArity VArgs VInter
         in
            RecordArity = {Width Value}
            VArgs = {MakeArgs 1 VHd VInter}
            VInter = vEquateRecord(_ {Label Value} RecordArity Reg VArgs VTl)
         elsecase {IsRecord Value} then
            fun {MakeArgs Fs VHd VTl}
               case Fs of F|Fr then VArg VInter in
                  VArg = {OzValueToVArg Value.F CS VHd VInter}
                  VArg|{MakeArgs Fr VInter VTl}
               [] nil then
                  VHd = VTl
                  nil
               end
            end
            RecordArity VArgs VInter
         in
            RecordArity = {Arity Value}
            VArgs = {MakeArgs RecordArity VHd VInter}
            VInter = vEquateRecord(_ {Label Value} RecordArity Reg VArgs VTl)
         end
      end
   in
      %% Nodes of this class may be used as subtrees in Constructions.
      %% Since the stored value must be ground, the `makeEquation' method
      %% suffices for code generation (records are always basic).

      class CodeGenOzValue
         prop final
         feat Val reg
         meth init(Value)
            self.Val = Value
         end
         meth reg($)
            self.reg
         end
         meth makeEquation(CS VO VHd VTl)
            {OzValueToVInstr self.Val {VO reg($)} CS VHd VTl}
         end
         meth assignRegToStructure(CS)
            {CS newReg(self.reg)}
         end
         meth makeRecordArgument(CS VHd VTl $) Value = self.Val in
            VHd = VTl
            case {IsNumber Value} then number(Value)
            elsecase {IsLiteral Value} then literal(Value)
            else value(self.reg)
            end
         end
         meth isConstruction($) Value = self.Val in
            {IsRecord Value} andthen {Not {IsAtom Value}}
         end
      end
   end
in
   class CodeGenStatement
      meth startCodeGen(Nodes Switches Reporter OldVs NewVs ?GPNs ?Code)
         CS StartAddr GRegs BodyCode0 NLiveRegs
         BodyCode1 BodyCode2 BodyCode StartLabel EndLabel
      in
         CS = {New CodeStore init(Switches Reporter)}
         {ForAll OldVs proc {$ V} {V setFreshReg(CS)} end}
         {ForAll NewVs proc {$ V} {V setFreshReg(CS)} end}
         {CS startDefinition()}
         {CodeGenList Nodes CS StartAddr nil}
         {CS endDefinition(StartAddr nil nil ?GRegs ?BodyCode0 ?NLiveRegs)}
         BodyCode0 = BodyCode1#BodyCode2
         case {Switches getSwitch(runwithdebugger $)} then
            BodyCode = callBI('Debug.breakpoint' nil#nil)|BodyCode1
         else
            BodyCode = BodyCode1
         end
         {CS getRegNames(GRegs ?GPNs)}
         StartLabel = {NewName}
         EndLabel = {NewName}
         Code =
         lbl(StartLabel)|
         definition(x(0) EndLabel
                    pid('Toplevel abstraction' 0 pos('' 0 0) [native]
                        NLiveRegs)
                    unit {List.mapInd GRegs fun {$ I _} g(I - 1) end}
                    BodyCode)|
         endDefinition(StartLabel)|
         {Append BodyCode2 [lbl(EndLabel) tailCall(x(0) 0)]}
      end
   end

   class CodeGenStepPoint
      meth codeGen(CS VHd VTl) VInter1 VInter2 in
         {CodeGenList @statements CS VInter1 VInter2}
         {StepPoint @coord @kind VHd VTl VInter1 VInter2}
      end
   end

   class CodeGenDeclaration
      meth codeGen(CS VHd VTl)
         {ForAll @localVars proc {$ V} {V setReg(CS)} end}
         case CS.debugInfoVarnamesSwitch then Regs Cont1 Cont2 in
            {MakePermanent @localVars ?Regs VHd Cont1}
            {CodeGenList @statements CS Cont1 Cont2}
            {Clear Regs Cont2 VTl}
         else
            {CodeGenList @statements CS VHd VTl}
         end
      end
   end

   class CodeGenSkipNode
      meth codeGen(CS VHd VTl) VInter in
         {StepPoint @coord 'skip' VHd VTl VInter VInter}
      end
   end

   class CodeGenEquation
      meth codeGen(CS VHd VTl)
         {@right makeEquation(CS @left VHd VTl)}
      end
   end

   class CodeGenConstruction from CodeGenRecord
      feat reg
      meth assignRegToStructure(CS)
         skip
      end
      meth makeEquationDescend(CS VHd VTl)
         VHd = VTl
      end
      meth makeVO(CS VHd VTl ?VO)
         VO = {NewPseudoVariableOccurrence CS}
         CodeGenRecord, makeEquation(CS VO VHd VTl)
      end
      meth makeRecordArgument(CS VHd VTl $) Label Feats in
         {@label getCodeGenValue(?Label)}
         Feats = {List.mapInd @args
                  fun {$ I Arg}
                     case Arg of F#_ then {F getCodeGenValue($)} else I end
                  end}
         case {Not @isOpen} andthen {IsDet Label} andthen {All Feats IsDet}
         then
            case Feats of nil then
               VHd = VTl
               literal(Label)
            else PairList Rec RecordArity VArgs in
               PairList = {List.zip Feats @args
                           fun {$ F Arg}
                              case Arg of _#T then F#T else F#Arg end
                           end}
               try
                  Rec = {List.toRecord Label PairList}
               catch failure(...) then C = {@label getCoord($)} in
                  {CS.reporter
                   error(coord: C kind: 'code generation error'
                         msg: 'duplicate feature in record construction')}
                  Rec = {FoldL PairList fun {$ In F#T} {AdjoinAt In F T} end
                         Label()}
               end
               case {IsTuple Rec} then
                  RecordArity = {Width Rec}
                  VArgs#VHd = {ForThread RecordArity 1 ~1
                               fun {$ In#VTl I} VArg VHd in
                                  {Rec.I makeRecordArgument(CS VHd VTl ?VArg)}
                                  (VArg|In)#VHd
                               end nil#VTl}
               else
                  RecordArity = {Arity Rec}
                  VArgs#VHd = {FoldR RecordArity
                               fun {$ F In#VTl} VArg VHd in
                                  {Rec.F makeRecordArgument(CS VHd VTl ?VArg)}
                                  (VArg|In)#VHd
                               end nil#VTl}
               end
               record(Label RecordArity VArgs)
            end
         else VO in
            VO = {NewPseudoVariableOccurrence CS}
            CodeGenRecord, makeEquation(CS VO VHd VTl)
            value({VO reg($)})
         end
      end
   end

   class CodeGenDefinition
      meth codeGen(CS VHd VTl)
         VHd0 VTl0 V FileName Line Col PrintName PredId OuterNLiveRegs
         PredicateRef StateReg
      in
         {@designator getVariable(?V)}
         case @coord of unit then FileName = '' Line = 1 Col = 0
         elseof C then FileName = C.1 Line = C.2 Col = C.3
         end
         PrintName = case {V getOrigin($)} of generated then @printName
                     else {V getPrintName($)}
                     end
         PredId = pid(PrintName {Length @formalArgs} pos(FileName Line Col)
                      case {Member native @procFlags} then [native]
                      else nil
                      end
                      OuterNLiveRegs)
\ifdef DEBUG_DEFS
         {Show PredId}
\endif
         PredicateRef = case {IsDet self.predicateRef} then
                           self.predicateRef
                        else unit
                        end
         case @isStateUsing then
            case CS.debugInfoVarnamesSwitch then
               {CS newSelfReg(?StateReg)}
            else
               {CS newReg(?StateReg)}
            end
         else
            StateReg = none
         end
         case @toCopy of unit then
            FormalRegs AllRegs BodyVInter BodyVInstr GRegs Code VInter
         in
            {CS startDefinition()}
            FormalRegs = {Map @formalArgs
                          fun {$ V}
                             {V setReg(CS)}
                             {V reg($)}
                          end}
            case CS.debugInfoVarnamesSwitch then Regs Cont1 Cont2 in
               {MakePermanent @formalArgs ?Regs BodyVInter Cont1}
               {CodeGenList @statements CS Cont1 Cont2}
               {Clear Regs Cont2 nil}
            else
               {CodeGenList @statements CS BodyVInter nil}
            end
            AllRegs = case @allVariables of nil then nil
                      else {Map @allVariables fun {$ V} {V reg($)} end}
                      end
            case StateReg of none then
               BodyVInstr = BodyVInter
               VHd0 = VInter
            else
               BodyVInstr = vSetSelf(_ StateReg BodyVInter)
               VHd0 = vGetSelf(_ StateReg VInter)
            end
            {CS endDefinition(BodyVInstr FormalRegs AllRegs ?GRegs ?Code
                              ?OuterNLiveRegs)}
            VInter = vDefinition(_ {V reg($)} PredId PredicateRef
                                 GRegs Code VTl0)
         else
            VInter FormalRegs AllRegs
            InnerBodyVInter InnerBodyVInstr InnerGRegs InnerCode
            InnerDefinitionReg InnerPredId InnerNLiveRegs
            OuterBodyVInstr OuterBodyVInter2 OuterGRegs OuterCode
         in
            {CS startDefinition()}
            FormalRegs = {Map @formalArgs
                          fun {$ V}
                             {V setReg(CS)}
                             {V reg($)}
                          end}
            {CS startDefinition()}
            {CodeGenList @statements CS InnerBodyVInter nil}
            AllRegs = case @allVariables of nil then nil
                      else {Map @allVariables fun {$ V} {V reg($)} end}
                      end
            case StateReg of none then
               InnerBodyVInstr = InnerBodyVInter
               VHd0 = VInter
            else
               InnerBodyVInstr = vSetSelf(_ StateReg InnerBodyVInter)
               VHd0 = vGetSelf(_ StateReg VInter)
            end
            {CS endDefinition(InnerBodyVInstr nil AllRegs
                              ?InnerGRegs ?InnerCode ?InnerNLiveRegs)}
            {CS newReg(?InnerDefinitionReg)}
            InnerPredId = {Adjoin PredId
                           pid({VirtualString.toAtom PrintName#'/body'} 0
                               4: {Filter @procFlags
                                   fun {$ F} F==once orelse F==native end}
                               5: InnerNLiveRegs)}
            case @toCopy of nil then Reg OuterBodyVInter1 in
               {CS newReg(?Reg)}
               OuterBodyVInstr = vEquateLiteral(_ nil Reg OuterBodyVInter1)
               OuterBodyVInter1 = vDefinitionCopy(_ Reg InnerDefinitionReg
                                                  InnerPredId unit
                                                  InnerGRegs InnerCode
                                                  OuterBodyVInter2)
            elseof Xs then
               fun {MakeCopyList Xs VHd VTl}
                  case Xs of X|Xr then ArgIn VInter1 ConsReg ConsArg1 in
                     ArgIn = {MakeCopyList Xr VHd VInter1}
                     {CS newReg(?ConsReg)}
                     ConsArg1 = case {Foreign.pointer.is X} then
                                   predicateRef(X)
                                elsecase {IsName X} then
                                   literal(X)
                                end
                     VInter1 = vEquateRecord(_ '|' 2 ConsReg [ConsArg1 ArgIn]
                                             VTl)
                     value(ConsReg)
                  [] nil then
                     VHd = VTl
                     literal(nil)
                  end
               end
               Reg OuterBodyVInter1
            in
               value(Reg) = {MakeCopyList Xs OuterBodyVInstr OuterBodyVInter1}
               OuterBodyVInter1 = vDefinitionCopy(_ Reg InnerDefinitionReg
                                                  InnerPredId unit
                                                  InnerGRegs InnerCode
                                                  OuterBodyVInter2)
            end
            OuterBodyVInter2 = vCall(_ InnerDefinitionReg nil unit nil)
            {CS endDefinition(OuterBodyVInstr FormalRegs AllRegs
                              ?OuterGRegs ?OuterCode ?OuterNLiveRegs)}
            VInter = vDefinition(_ {V reg($)} PredId PredicateRef
                                 OuterGRegs OuterCode VTl0)
         end
         {StepPoint @coord 'definition' VHd VTl VHd0 VTl0}
         statements <- unit   % hand them to the garbage collector
      end
   end
   class CodeGenFunctionDefinition
   end
   class CodeGenClauseBody
      meth codeGen(CS VHd VTl)
         % code for the clause body is only generated when it is applied
         % (see class CodeGenProcedureToken, method codeGenApplication)
         VHd = VTl
      end
   end

   class CodeGenApplication
      meth codeGen(CS VHd VTl)
         case {IsDet self.codeGenMakeEquateLiteral} then VHd0 VTl0 in
            % the application is either a toplevel application of NewName
            % or any application of NewUniqueName:
            VHd0 = vEquateLiteral(_ self.codeGenMakeEquateLiteral
                                  {{List.last @actualArgs} reg($)} VTl0)
            {StepPoint @coord 'name generation' VHd VTl VHd0 VTl0}
         else
            {MakeApplication @designator @coord @actualArgs CS VHd VTl}
         end
      end
   end

   class CodeGenBoolCase
      meth codeGen(CS VHd VTl) True TrueValue False FalseValue ErrAddr in
         True = {GetExpansionOcc '`true`' self @coord CS}
         {True getCodeGenValue(?TrueValue)}
         False = {GetExpansionOcc '`false`' self @coord CS}
         {False getCodeGenValue(?FalseValue)}
         ErrAddr = self.noBoolShared
         case {IsFree ErrAddr} then Label Count Addr in
            ErrAddr = vShared(_ Label Count Addr)
            {CS newLabel(?Label)}
            Count = {NewCell 0}
            {MakeException self boolCaseType @coord nil CS Addr nil}
         else skip
         end
         case {IsDet TrueValue} andthen TrueValue == true
            andthen {IsDet FalseValue} andthen FalseValue == false
         then Value in
            {@arbiter getCodeGenValue(?Value)}
            case {IsDet Value} andthen Value == true
            then {@consequent codeGen(CS VHd VTl)}
            elsecase {IsDet Value} andthen Value == false
            then {@alternative codeGenNoShared(CS VHd VTl)}
            else ThenAddr AltAddr in
               {@consequent codeGen(CS ThenAddr nil)}
               {@alternative codeGenShared(CS AltAddr nil)}
               VHd = vTestBool(_ {@arbiter reg($)} ThenAddr AltAddr ErrAddr
                               @coord VTl _)
            end
         else
            Cont1 Cont2 GuardVInstr1 BodyVInstr1 GuardVInstr2 BodyVInstr2
            AllocatesRS VClause1 VClause2
         in
            {True makeEquation(CS @arbiter GuardVInstr1 Cont1)}
            Cont1 = vAsk(_ nil)
            {@consequent codeGen(CS BodyVInstr1 nil)}
            {False makeEquation(CS @arbiter GuardVInstr2 Cont2)}
            Cont2 = vAsk(_ nil)
            {@alternative codeGenNoShared(CS BodyVInstr2 nil)}
            {CS makeRegSet(?AllocatesRS)}
            {CS enterVs([@arbiter True False] AllocatesRS)}
            VClause1 = _#GuardVInstr1#BodyVInstr1
            VClause2 = _#GuardVInstr2#BodyVInstr2
            VHd = vCreateCond(_ [VClause1 VClause2] ErrAddr VTl @coord
                              AllocatesRS _)
         end
      end
   end

   class CodeGenBoolClause
      meth codeGen(CS VHd VTl)
         {CodeGenList @statements CS VHd VTl}
      end
   end

   class CodeGenPatternCase
      meth codeGen(CS VHd VTl)
         case {All @clauses fun {$ Clause} {Clause isSwitchable($)} end} then
            TestReg SHT
         in
            {@arbiter reg(?TestReg)}
            SHT = {New SwitchHashTable
                   init(@coord TestReg @alternative @arbiter CS)}
            {ForAll @clauses
             proc {$ Clause} {Clause makeSwitchable(TestReg CS SHT)} end}
            {SHT codeGen(VHd VTl)}
         else AllocatesRS VClauses AltVInstr in
            {CS makeRegSet(?AllocatesRS)}
            VClauses = {Map @clauses
                        fun {$ Clause}
                           {CS enterVs({Clause getPatternGlobalVars($)}
                                       AllocatesRS)}
                           {Clause makeCondClause(CS @arbiter $)}
                        end}
            {@alternative
             codeGenWithArbiterNoShared(CS @arbiter AltVInstr nil)}
            VHd = vCreateCond(_ VClauses AltVInstr VTl @coord nil _)
         end
      end
   end

   class CodeGenPatternClause
      meth isSwitchable($)
         {@pattern isSwitchable($)}
      end
      meth makeSwitchable(Reg CS SHT) Msg in
         %--** CS.debugInfoVarnamesSwitch!
         {@pattern makeSwitchable(Reg @localVars @statements CS ?Msg)}
         {ForAll @localVars
          proc {$ V} Reg = {V reg($)} in
             case {IsDet Reg} then skip
             else {CS newVariableReg(V ?Reg)}
             end
          end}
         {SHT Msg}
      end
      meth makeCondClause(CS VO $)
         GuardVHd GuardVTl GuardVInstr Cont BodyVInstr
      in
         {ForAll @localVars proc {$ V} {V setReg(CS)} end}
         {@pattern makeEquation(CS VO GuardVHd GuardVTl)}
         case {GuardNeedsThread GuardVHd} then Coord in
            {@pattern getCoord(?Coord)}
            GuardVTl = nil
            GuardVInstr = vThread(_ GuardVHd Coord Cont _)
         else
            GuardVTl = Cont
            GuardVInstr = GuardVHd
         end
         Cont = vAsk(_ nil)
         case CS.debugInfoVarnamesSwitch then Regs Cont3 Cont4 in
            {MakePermanent @localVars ?Regs BodyVInstr Cont3}
            {CodeGenList @statements CS Cont3 Cont4}
            {Clear Regs Cont4 nil}
         else
            {CodeGenList @statements CS BodyVInstr nil}
         end
         _#GuardVInstr#BodyVInstr
      end
   end

   class CodeGenRecordPattern from CodeGenRecord
      feat reg
      meth reg($)
         self.reg
      end
      meth isSwitchable($)
         {Not @isOpen}
         andthen {IsDet {@label getCodeGenValue($)}}
         andthen {All @args
                  fun {$ Arg}
                     case Arg of F#_ then {IsDet {F getCodeGenValue($)}}
                     else true
                     end
                  end}
      end
      meth makeSwitchable(Reg LocalVars Body CS $) TheLabel PairList Rec in
         {@label getCodeGenValue(?TheLabel)}
         PairList = {List.mapInd @args
                     fun {$ I Arg}
                        case Arg of F#A then {F getCodeGenValue($)}#A
                        else I#Arg
                        end
                     end}
         try
            Rec = {List.toRecord TheLabel PairList}
         catch failure(...) then C = {@label getCoord($)} in
            {CS.reporter
             error(coord: C kind: 'code generation error'
                   msg: 'duplicate feature in record construction')}
            Rec = {FoldL PairList fun {$ In F#T} {AdjoinAt In F T} end
                   TheLabel()}
         end
         case {IsLiteral Rec} then
            addScalar(Rec LocalVars Body)
         else
            addRecord({Record.map Rec fun {$ _} '' end}
                      LocalVars#{Record.toList Rec}#{@label getCoord($)}#Body)
         end
      end
      meth makeGetArg(CS PatternVs V1Hd V1Tl V2Hd V2Tl ?NewPatternVs) Reg VO in
         {CS newReg(?Reg)}
         V1Hd = vGetVariable(_ Reg V1Tl)
         VO = {New PseudoVariableOccurrence init(Reg)}
         CodeGenRecordPattern, makeEquation(CS VO V2Hd V2Tl)
         CodeGenRecordPattern, addPatternVs(PatternVs ?NewPatternVs)
      end
      meth addPatternVs(PatternVs $)
         {FoldL @args
          fun {$ PatternVs Arg}
             case Arg of _#P then {P addPatternVs(PatternVs $)}
             else {Arg addPatternVs(PatternVs $)}
             end
          end PatternVs}
      end
      meth assignRegToStructure(CS)
         {CS newReg(self.reg)}
      end
      meth makeEquationDescend(CS VHd VTl)
         {FoldL @args
          proc {$ VHd Arg VTl} T in
             T = case Arg of _#X then X else Arg end
             case {T isConstruction($)} then VO in
                VO = {New PseudoVariableOccurrence init({T reg($)})}
                {T makeEquation(CS VO VHd VTl)}
             else
                VHd = VTl
             end
          end VHd VTl}
      end
      meth makeVO(CS VHd VTl ?VO)
         VHd = VTl
         VO = {New PseudoVariableOccurrence init(self.reg)}
      end
      meth makeRecordArgument(CS VHd VTl $)
         VHd = VTl
         value(self.reg)
      end
   end

   class CodeGenEquationPattern
      meth getCodeGenValue($)
         {@right getCodeGenValue($)}
      end
      meth reg($)
         {@right reg($)}
      end
      meth isSwitchable($)
         {@right isSwitchable($)}
      end
      meth makeSwitchable(Reg LocalVars Body CS $)
         {{@left getVariable($)} reg(Reg)}   % this has the effect of setting
         {@right makeSwitchable(Reg LocalVars Body CS $)}
      end
      meth makeGetArg(CS PatternVs V1Hd V1Tl V2Hd V2Tl ?NewPatternVs)
         V Reg VO
      in
         {@left getVariable(?V)}
         {@left reg(?Reg)}
         V1Hd = vGetVariable(_ Reg V1Tl)
         case {Member V PatternVs} then
            {@right addPatternVs(PatternVs ?NewPatternVs)}
         else
            {@right addPatternVs(V|PatternVs ?NewPatternVs)}
         end
         VO = {New PseudoVariableOccurrence init(Reg)}
         {@right makeEquation(CS VO V2Hd V2Tl)}
      end
      meth addPatternVs(PatternVs ?NewPatternVs) V in
         {@left getVariable(?V)}
         case {Member V PatternVs} then
            {@right addPatternVs(PatternVs ?NewPatternVs)}
         else
            {@right addPatternVs(V|PatternVs ?NewPatternVs)}
         end
      end
      meth makeEquation(CS VO VHd VTl) VInter in
         {MakeUnify {VO reg($)} {@left reg($)} VHd VInter}
         {@right makeEquation(CS VO VInter VTl)}
      end
      meth assignRegToStructure(CS)
         @right.reg = {{@left getVariable($)} reg($)}
      end
      meth makeRecordArgument(CS VHd VTl $)
         {@left makeRecordArgument(CS VHd VTl $)}
      end
   end

   class CodeGenAbstractElse
      feat shared
   end
   class CodeGenElseNode
      attr localVars
      meth codeGenInit(LocalVars Statements)
         localVars <- LocalVars
         statements <- Statements
      end
      meth codeGenShared(CS VHd VTl)
         VHd = self.shared
         VTl = nil
         case {IsFree VHd} then Label Count Addr in
            VHd = vShared(_ Label Count Addr)
            {CS newLabel(?Label)}
            Count = {NewCell 0}
            case CS.debugInfoVarnamesSwitch andthen {IsDet @localVars} then
               Regs Cont1 Cont2 in
               {MakePermanent @localVars ?Regs Addr Cont1}
               {CodeGenList @statements CS Cont1 Cont2}
               {Clear Regs Cont2 nil}
            else
               {CodeGenList @statements CS Addr nil}
            end
         else skip
         end
      end
      meth codeGenWithArbiterShared(CS VO VHd VTl)
         CodeGenElseNode, codeGenShared(CS VHd VTl)
      end
      meth codeGenNoShared(CS VHd VTl)
         case CS.debugInfoVarnamesSwitch andthen {IsDet @localVars} then
            Regs Cont1 Cont2 in
            {MakePermanent @localVars ?Regs VHd Cont1}
            {CodeGenList @statements CS Cont1 Cont2}
            {Clear Regs Cont2 VTl}
         else
            {CodeGenList @statements CS VHd VTl}
         end
      end
      meth codeGenWithArbiterNoShared(CS VO VHd VTl)
         CodeGenElseNode, codeGenNoShared(CS VHd VTl)
      end
   end
   class CodeGenNoElse
      meth codeGenShared(CS VHd VTl)
         VHd = self.shared
         VTl = nil
         case {IsFree VHd} then Label Count Addr in
            VHd = vShared(_ Label Count Addr)
            {CS newLabel(?Label)}
            Count = {NewCell 0}
            {MakeException self noElse @coord nil CS Addr nil}
         else skip
         end
      end
      meth codeGenWithArbiterShared(CS VO VHd VTl)
         VHd = self.shared
         VTl = nil
         case {IsFree VHd} then Label Count Addr in
            VHd = vShared(_ Label Count Addr)
            {CS newLabel(?Label)}
            Count = {NewCell 0}
            {MakeException self noElse @coord [VO] CS Addr nil}
         else skip
         end
      end
      meth codeGenNoShared(CS VHd VTl)
         {MakeException self noElse @coord nil CS VHd VTl}
      end
      meth codeGenWithArbiterNoShared(CS VO VHd VTl)
         {MakeException self noElse @coord [VO] CS VHd VTl}
      end
   end

   class CodeGenThreadNode
      meth codeGen(CS VHd VTl) BodyVInstr in
         {CodeGenList @statements CS BodyVInstr nil}
         VHd = vThread(_ BodyVInstr @coord VTl _)
      end
   end

   class CodeGenTryNode
      meth codeGen(CS VHd VTl) TryBodyVInstr CatchBodyVInstr in
         {CodeGenList @tryStatements CS TryBodyVInstr vPopEx(_ @coord nil)}
         {@exception setReg(CS)}
         case CS.debugInfoVarnamesSwitch then Regs Cont1 Cont2 in
            {MakePermanent [@exception] ?Regs CatchBodyVInstr Cont1}
            {CodeGenList @catchStatements CS Cont1 Cont2}
            {Clear Regs Cont2 nil}
         else
            {CodeGenList @catchStatements CS CatchBodyVInstr nil}
         end
         VHd = vExHandler(_ TryBodyVInstr {@exception reg($)}
                          CatchBodyVInstr @coord VTl _)
      end
   end

   class CodeGenLockNode
      meth codeGen(CS VHd VTl) SharedData Cont1 in
         VHd = vLockThread(_ {@lockVar reg($)} @coord Cont1 SharedData)
         {CodeGenList @statements CS Cont1 vLockEnd(_ @coord VTl SharedData)}
      end
   end

   class CodeGenClassNode
      meth codeGen(CS VHd VTl)
         VHd0 VTl0 Class From Attr Feat Prop PN Meth PrintName
         VInter1 VInter2 VInter3
      in
         Class = {GetExpansionOcc '`class`' self @coord CS}
         local Cont1 Cont2 Cont3 in
            {MakeFromProp @parents CS VHd0 Cont1 ?From}
            {MakeFromProp @properties CS Cont1 Cont2 ?Prop}
            {MakeAttrFeat 'attr' @attributes self @coord CS Cont2 Cont3 ?Attr}
            {MakeAttrFeat 'feat' @features self @coord CS Cont3 VInter1 ?Feat}
         end
         case @printName == '' then
            {{@designator getVariable($)} getPrintName(?PN)}
         else
            PN = @printName
         end
         Meth = {NewPseudoVariableOccurrence CS}
         case @methods of _|_ then
            fun {MakeMethods Methods VHd VTl}
               case Methods of M|Mr then MethReg VInter in
                  {CS newReg(?MethReg)}
                  {M makeQuadruple(PN CS MethReg @isToplevel VHd VInter)}
                  value(MethReg)|{MakeMethods Mr VInter VTl}
               [] nil then
                  VHd = VTl
                  nil
               end
            end
            Cont Args
         in
            Args = {MakeMethods @methods VInter1 Cont}
            Cont = vEquateRecord(_ '#' {Length @methods} {Meth reg($)}
                                 Args VInter2)
         [] nil then
            VInter1 = vEquateLiteral(_ '#' {Meth reg($)} VInter2)
         end
         methods <- unit   % hand them to the garbage collector
         local Reg in
            {CS newReg(?Reg)}
            VInter2 = vEquateLiteral(_ PN Reg VInter3)
            PrintName = {New PseudoVariableOccurrence init(Reg)}
         end
         {MakeApplication Class {CoordNoDebug @coord}
          [From Meth Attr Feat Prop PrintName @designator] CS VInter3 VTl0}
         {StepPoint @coord 'definition' VHd VTl VHd0 VTl0}
      end
   end

   class CodeGenMethod
      feat hasDefaults MessagePatternVO
      meth makeQuadruple(PrintName CS Reg IsToplevel VHd VTl)
         RecordArity FileName Line Col SlowMeth FastMeth VInter1 VInter2
         X = unit
      in
         local PairList Rec in
            % Sort the formal arguments by feature
            % (important for order of fast methods' formal parameters):
            PairList = {Map @formalArgs
                        fun {$ Formal}
                           {{Formal getFeature($)} getCodeGenValue($)}#Formal
                        end}
            try
               Rec = {List.toRecord someLabel PairList}
               RecordArity = case {IsTuple Rec} then {Width Rec}
                             else {Arity Rec}
                             end
               formalArgs <- {Record.toList Rec}
            catch failure(...) then C = {@label getCoord($)} in
               {CS.reporter
                error(coord: C kind: 'code generation error'
                      msg: 'duplicate feature in record construction')}
               RecordArity = {Length @formalArgs}
            end
         end
         self.hasDefaults = {Some @formalArgs
                             fun {$ Formal} {Formal hasDefault($)} end}
         case @coord of unit then FileName = '' Line = 1 Col = 0
         elseof C then FileName = C.1 Line = C.2 Col = C.3
         end
         local PredId NLiveRegs FormalRegs AllRegs BodyVInstr GRegs Code in
            PredId = pid({String.toAtom
                          {VirtualString.toString
                           PrintName#','#{@label methPrintName($)}#'/fast'}}
                         RecordArity pos(FileName Line Col) nil NLiveRegs)
\ifdef DEBUG_DEFS
            {Show PredId}
\endif
            {CS startDefinition()}
            FormalRegs = {Map @formalArgs
                          fun {$ Formal} V = {Formal getVariable($)} in
                             {V setFreshReg(CS)}
                             {V reg($)}
                          end}
            AllRegs = case @allVariables of nil then nil
                      else {Map @allVariables fun {$ V} {V reg($)} end}
                      end
            case CS.debugInfoVarnamesSwitch then
               StateReg Vs Regs Cont1 Cont2 Cont3 Cont4 Cont5
            in
               {CS newSelfReg(?StateReg)}
               BodyVInstr = vMakePermanent(_ [StateReg] Cont1)
               Cont1 = vGetSelf(_ StateReg Cont2)
               Vs = {Map @formalArgs fun {$ F} {F getVariable($)} end}
               {MakePermanent Vs ?Regs Cont2 Cont3}
               {CodeGenList @statements CS Cont3 Cont4}
               {Clear Regs Cont4 Cont5}
               {Clear [StateReg] Cont5 nil}
            else
               {CodeGenList @statements CS BodyVInstr nil}
            end
            statements <- unit   % hand it to the garbage collector
            {CS endDefinition(BodyVInstr FormalRegs AllRegs ?GRegs ?Code
                              ?NLiveRegs)}
            {CS newReg(?FastMeth)}
            VHd = vDefinition(_ FastMeth PredId @predicateRef GRegs Code
                              VInter1)
         end
         local
            PredId NLiveRegs MessageVO FormalRegs BodyVInstr GRegs
            Code Cont1 Cont2 Cont3
         in
            PredId = pid({String.toAtom
                          {VirtualString.toString
                           PrintName#','#{@label methPrintName($)}#'/slow'}}
                         1 pos(FileName Line Col) nil NLiveRegs)
\ifdef DEBUG_DEFS
            {Show PredId}
\endif
            CodeGenMethod, makeArityCheckInit(CS VInter1 Cont1)
            {CS startDefinition()}
            MessageVO = {NewPseudoVariableOccurrence CS}
            FormalRegs = [MessageVO.reg]
            CodeGenMethod, makeArityCheck(MessageVO CS BodyVInstr Cont2)
            {FoldL @formalArgs
             proc {$ VHd Formal VTl}
                {Formal bindMethFormal(MessageVO CS self VHd VTl)}
             end Cont2 Cont3}
            case IsToplevel then
               Cont3 = vFastCall(_ @predicateRef
                                 {Map @formalArgs
                                  fun {$ Formal}
                                     {{Formal getVariable($)} reg($)}
                                  end} unit nil)
            else
               {MakeApplication
                {New PseudoVariableOccurrence init(FastMeth)}
                {CoordNoDebug @coord}
                {Map @formalArgs
                 fun {$ Formal}
                    {New PseudoVariableOccurrence
                     init({{Formal getVariable($)} reg($)})}
                 end} CS Cont3 nil}
            end
            {CS endDefinition(BodyVInstr FormalRegs nil ?GRegs ?Code
                              ?NLiveRegs)}
            {CS newReg(?SlowMeth)}
            Cont1 = vDefinition(_ SlowMeth PredId unit GRegs Code VInter2)
         end
         case self.hasDefaults then Args Constr VO VInter3 in
            Args = {Map @formalArgs
                    fun {$ Formal}
                       {Formal getFeature($)}#{Formal getDefault(CS self $)}
                    end}
            Constr = {New Core.recordPattern init(@label Args false)}
            Constr.expansionOccs.'`tuple`' = self.expansionOccs.'`tuple`'
            Constr.expansionOccs.'`record`' = self.expansionOccs.'`record`'
            VO = {NewPseudoVariableOccurrence CS}
            {Constr makeEquation(CS VO VInter2 VInter3)}
            VInter3 = vEquateRecord(_ '#' [1 2 default fast] Reg
                                    [{@label makeRecordArgument(CS X X $)}
                                     value(SlowMeth) value({VO reg($)})
                                     value(FastMeth)] VTl)
         else
            VInter2 = vEquateRecord(_ '#' [1 2 fast] Reg
                                    [{@label makeRecordArgument(CS X X $)}
                                     value(SlowMeth) value(FastMeth)] VTl)
         end
      end
      meth makeArityCheck(MessageVO CS VHd VTl)
         case self.hasDefaults then AritySublist in
            AritySublist = {GetExpansionOcc '`aritySublist`' self @coord CS}
            {MakeApplication AritySublist {CoordNoDebug @coord}
             [MessageVO self.MessagePatternVO] CS VHd VTl}
         else NArgs LabelValue in
            NArgs = {Length @formalArgs}
            {@label getCodeGenValue(?LabelValue)}
            case NArgs == 0 andthen {IsDet LabelValue} then
               VHd = vEquateLiteral(_ LabelValue {MessageVO reg($)} VTl)
            else Reg VO WidthVO Cont1 in
               {CS newReg(?Reg)}
               VO = {New PseudoVariableOccurrence init(Reg)}
               WidthVO = {GetExpansionOcc '`width`' self @coord CS}
               VHd = vEquateNumber(_ NArgs Reg Cont1)
               {MakeApplication WidthVO {CoordNoDebug @coord}
                [MessageVO VO] CS Cont1 VTl}
            end
         end
      end
      meth makeArityCheckInit(CS VHd VTl)
         self.MessagePatternVO = {New PseudoVariableOccurrence
                                  init({CS newReg($)})}
         case self.hasDefaults then LabelReg LabelVO Constr in
            {CS newReg(?LabelReg)}
            LabelVO = {New PseudoVariableOccurrence init(LabelReg)}
            LabelVO.value = 'messagePattern'
            Constr = {New Core.construction
                      init(LabelVO
                           {Map @formalArgs
                            fun {$ Formal} VO in
                               VO = {NewPseudoVariableOccurrence CS}
                               VO.value = unit
                               {Formal getFeature($)}#VO
                            end} false)}
            Constr.expansionOccs.'`tuple`' = self.expansionOccs.'`tuple`'
            Constr.expansionOccs.'`record`' = self.expansionOccs.'`record`'
            {Constr makeEquation(CS self.MessagePatternVO VHd VTl)}
         else
            VHd = VTl
         end
      end
   end
   class CodeGenMethodWithDesignator
      meth makeQuadruple(PrintName CS Reg IsToplevel VHd VTl)
         FileName Line Col X = unit SlowMeth VInter1
      in
         self.hasDefaults = {Some @formalArgs
                             fun {$ Formal} {Formal hasDefault($)} end}
         case @coord of unit then FileName = '' Line = 1 Col = 0
         elseof C then FileName = C.1 Line = C.2 Col = C.3
         end
         local
            PredId NLiveRegs MessageReg MessageVO BodyVInstr
            FormalRegs AllRegs GRegs Code Cont1 Cont2 Cont3 Cont4 Cont5
         in
            PredId = pid({String.toAtom
                          {VirtualString.toString
                           PrintName#','#{@label methPrintName($)}}}
                         1 pos(FileName Line Col) nil NLiveRegs)
\ifdef DEBUG_DEFS
            {Show PredId}
\endif
            case @isOpen then
               VHd = Cont1
            else
               CodeGenMethod, makeArityCheckInit(CS VHd Cont1)
            end
            {CS startDefinition()}
            {@messageDesignator setReg(CS)}
            {@messageDesignator reg(?MessageReg)}
            MessageVO = {New PseudoVariableOccurrence init(MessageReg)}
            FormalRegs = [MessageReg]
            AllRegs = case @allVariables of nil then nil
                      else {Map @allVariables fun {$ V} {V reg($)} end}
                      end
            case @isOpen then
               Cont2 = Cont3
            else
               CodeGenMethod, makeArityCheck(MessageVO CS Cont2 Cont3)
            end
            {FoldL @formalArgs
             proc {$ VHd Formal VTl}
                {Formal bindMethFormal(MessageVO CS self VHd VTl)}
             end Cont3 Cont4}
            {CodeGenList @statements CS Cont4 Cont5}
            case CS.debugInfoVarnamesSwitch then
               StateReg Vs Regs Cont01 Cont02 Cont05
            in
               {CS newSelfReg(?StateReg)}
               BodyVInstr = vMakePermanent(_ [StateReg] Cont01)
               Cont01 = vGetSelf(_ StateReg Cont02)
               Vs = @messageDesignator|{Map @formalArgs
                                        fun {$ F} {F getVariable($)} end}
               {MakePermanent Vs ?Regs Cont02 Cont2}
               {Clear [StateReg] Cont5 Cont05}
               {Clear Regs Cont05 nil}
            else
               BodyVInstr = Cont2
               Cont5 = nil
            end
            {CS endDefinition(BodyVInstr FormalRegs AllRegs ?GRegs ?Code
                              ?NLiveRegs)}
            {CS newReg(?SlowMeth)}
            Cont1 = vDefinition(_ SlowMeth PredId unit GRegs Code VInter1)
         end
         VInter1 = vEquateRecord(_ '|' 2 Reg
                                 [{@label makeRecordArgument(CS X X $)}
                                  value(SlowMeth)] VTl)
      end
   end

   class CodeGenMethFormal
      meth getDefault(CS ExpansionOccNode $) C in
         {@feature getCoord(?C)}
         {GetExpansionOcc '`ooRequiredArg`' ExpansionOccNode C CS}
      end
      meth bindMethFormal(MessageVO CS ExpansionOccNode VHd VTl)
         C Dot FeatureVO ArgVO VInter
      in
         {@arg setFreshReg(CS)}
         {@feature getCoord(?C)}
         Dot = {GetExpansionOcc '`.`' ExpansionOccNode C CS}
         ArgVO = {New PseudoVariableOccurrence init({@arg reg($)})}
         {@feature makeVO(CS VHd VInter ?FeatureVO)}
         {MakeApplication Dot {CoordNoDebug C}
          [MessageVO FeatureVO ArgVO] CS VInter VTl}
      end
   end
   class CodeGenMethFormalOptional
      meth getDefault(CS ExpansionOccNode $) C in
         {@feature getCoord(?C)}
         {GetExpansionOcc '`ooDefaultVar`' ExpansionOccNode C CS}
      end
      meth bindMethFormal(MessageVO CS ExpansionOccNode VHd VTl)
         {@arg setFreshReg(CS)}
         case @isInitialized then
            VHd = VTl
         else
            Coord CND HasFeature Dot ArbiterReg ArbiterVO
            FeatureVO ArgVO ThenVInstr ElseVInstr ErrVInstr Cont1 Cont2
         in
            {@arg getCoord(?Coord)}
            CND = {CoordNoDebug Coord}
            HasFeature = {GetExpansionOcc '`hasFeature`' ExpansionOccNode
                          Coord CS}
            Dot = {GetExpansionOcc '`.`' ExpansionOccNode Coord CS}
            {CS newReg(?ArbiterReg)}
            ArbiterVO = {New PseudoVariableOccurrence init(ArbiterReg)}
            {@feature makeVO(CS VHd Cont1 ?FeatureVO)}
            ArgVO = {New PseudoVariableOccurrence init({@arg reg($)})}
            {MakeApplication Dot CND
             [MessageVO FeatureVO ArgVO] CS ThenVInstr nil}
            ElseVInstr = nil
            {MakeException ExpansionOccNode boolCaseType Coord nil CS
             ErrVInstr nil}
            {MakeApplication HasFeature CND
             [MessageVO FeatureVO ArbiterVO] CS Cont1 Cont2}
            Cont2 = vTestBool(_ ArbiterReg ThenVInstr ElseVInstr ErrVInstr
                              unit VTl _)
         end
      end
   end
   class CodeGenMethFormalWithDefault
      meth getDefault(CS ExpansionOccNode $)
         {New CodeGenOzValue init(@default)}
      end
      meth bindMethFormal(MessageVO CS ExpansionOccNode VHd VTl)
         Coord CND HasFeature Dot ArbiterReg ArbiterVO
         FeatureVO ArgVO ThenVInstr Default ElseVInstr ErrVInstr Cont1 Cont2
      in
         {@arg setFreshReg(CS)}
         {@arg getCoord(?Coord)}
         CND = {CoordNoDebug Coord}
         HasFeature = {GetExpansionOcc '`hasFeature`' ExpansionOccNode
                       Coord CS}
         Dot = {GetExpansionOcc '`.`' ExpansionOccNode Coord CS}
         {CS newReg(?ArbiterReg)}
         ArbiterVO = {New PseudoVariableOccurrence init(ArbiterReg)}
         {@feature makeVO(CS VHd Cont1 ?FeatureVO)}
         ArgVO = {New PseudoVariableOccurrence init({@arg reg($)})}
         {MakeApplication Dot CND
          [MessageVO FeatureVO ArgVO] CS ThenVInstr nil}
         Default = {New CodeGenOzValue init(@default)}
         {Default makeEquation(CS ArgVO ElseVInstr nil)}
         {MakeException ExpansionOccNode boolCaseType Coord nil CS
          ErrVInstr nil}
         {MakeApplication HasFeature CND
          [MessageVO FeatureVO ArbiterVO] CS Cont1 Cont2}
         Cont2 = vTestBool(_ ArbiterReg ThenVInstr ElseVInstr ErrVInstr
                           unit VTl _)
      end
   end

   class CodeGenObjectLockNode
      meth codeGen(CS VHd VTl)
         OOGetLock Reg Arg SharedData Cont1 Cont2
      in
         OOGetLock = {GetExpansionOcc '`ooGetLock`' self @coord CS}
         {CS newReg(?Reg)}
         Arg = {New PseudoVariableOccurrence init(Reg)}
         {MakeApplication OOGetLock {CoordNoDebug @coord} [Arg] CS VHd Cont1}
         Cont1 = vLockThread(_ Reg @coord Cont2 SharedData)
         {CodeGenList @statements CS Cont2 vLockEnd(_ @coord VTl SharedData)}
      end
   end

   class CodeGenGetSelf
      meth codeGen(CS VHd VTl)
         VHd = vGetSelf(_ {@destination reg($)} VTl)
      end
   end

   class CodeGenFailNode
      meth codeGen(CS VHd VTl) VInter in
         {StepPoint @coord 'fail' VHd VTl vFailure(_ VInter) VInter}
      end
   end

   class CodeGenIfNode
      meth codeGen(CS VHd VTl) AllocatesRS in
         {CS makeRegSet(?AllocatesRS)}
         case @clauses of [Clause] then
            GuardVInstr VTl2 Cont BodyVInstr AltVInstr
         in
            {CS enterVs({Clause getGuardGlobalVars($)} AllocatesRS)}
            {Clause codeGen(CS ?GuardVInstr ?VTl2 ?Cont ?BodyVInstr)}
            {@alternative codeGenNoShared(CS AltVInstr nil)}
            case {GuardIsShallow GuardVInstr} then
               VTl2 = nil
               VHd = vShallowGuard(_ GuardVInstr BodyVInstr AltVInstr
                                   @coord VTl AllocatesRS _)
            else
               VTl2 = Cont
               VHd = vCreateCond(_ [_#GuardVInstr#BodyVInstr]
                                 AltVInstr VTl @coord AllocatesRS _)
            end
         else VClauses AltVInstr in
            VClauses = {Map @clauses
                        fun {$ Clause} GuardVInstr VTl Cont BodyVInstr in
                           {CS enterVs({Clause getGuardGlobalVars($)}
                                       AllocatesRS)}
                           {Clause
                            codeGen(CS ?GuardVInstr ?VTl ?Cont ?BodyVInstr)}
                           VTl = Cont
                           _#GuardVInstr#BodyVInstr
                        end}
            {@alternative codeGenNoShared(CS AltVInstr nil)}
            VHd = vCreateCond(_ VClauses AltVInstr VTl @coord AllocatesRS _)
         end
      end
   end

   class CodeGenChoicesAndDisjunctions
      meth codeGen(Label CS VHd VTl) AllocatesRS VClauses in
         {CS makeRegSet(?AllocatesRS)}
         VClauses = {Map @clauses
                     fun {$ Clause} GuardVInstr VTl Cont BodyVInstr in
                        {CS enterVs({Clause getGuardGlobalVars($)}
                                    AllocatesRS)}
                        {Clause
                         codeGen(CS ?GuardVInstr ?VTl ?Cont ?BodyVInstr)}
                        VTl = Cont
                        _#GuardVInstr#BodyVInstr
                     end}
         VHd = Label(_ VClauses VTl @coord AllocatesRS _)
      end
   end
   class CodeGenOrNode
      meth codeGen(CS VHd VTl)
         CodeGenChoicesAndDisjunctions, codeGen(vCreateOr CS VHd VTl)
      end
   end
   class CodeGenDisNode
      meth codeGen(CS VHd VTl)
         CodeGenChoicesAndDisjunctions, codeGen(vCreateEnumOr CS VHd VTl)
      end
   end
   class CodeGenChoiceNode
      meth codeGen(CS VHd VTl)
         CodeGenChoicesAndDisjunctions, codeGen(vCreateChoice CS VHd VTl)
      end
   end

   class CodeGenClause
      meth codeGen(CS ?GuardVInstr ?VTl ?Cont ?BodyVInstr) GuardVHd GuardVTl in
         {ForAll @localVars proc {$ V} {V setReg(CS)} end}
         {CodeGenList @guard CS GuardVHd GuardVTl}
         case {GuardNeedsThread GuardVHd} then Coord in
            {@guard.1 getCoord(?Coord)}
            GuardVTl = nil
            GuardVInstr = vThread(_ GuardVHd Coord VTl _)
         else
            GuardVTl = VTl
            GuardVInstr = GuardVHd
         end
         Cont = case @kind of ask then vAsk(_ nil)
                [] wait then vWait(_ nil)
                [] waitTop then vWaitTop(_ nil)
                end
         case CS.debugInfoVarnamesSwitch then Regs Cont3 Cont4 in
            {MakePermanent @localVars ?Regs BodyVInstr Cont3}
            {CodeGenList @statements CS Cont3 Cont4}
            {Clear Regs Cont4 nil}
         else
            {CodeGenList @statements CS BodyVInstr nil}
         end
      end
   end

   class CodeGenValueNode
      meth getCodeGenValue($)
         @value
      end
      meth isSwitchable($)
         true
      end
      meth makeSwitchable(Reg LocalVars Body CS $)
         addScalar({self getCodeGenValue($)} LocalVars Body)
      end
      meth makeGetArg(CS PatternVs V1Hd V1Tl V2Hd V2Tl ?NewPatternVs) Reg VO in
         {CS newReg(?Reg)}
         V1Hd = vGetVariable(_ Reg V1Tl)
         VO = {New PseudoVariableOccurrence init(Reg)}
         {self makeEquation(CS VO V2Hd V2Tl)}
         NewPatternVs = PatternVs
      end
      meth addPatternVs(PatternVs ?NewPatternVs)
         NewPatternVs = PatternVs
      end
      meth assignRegToStructure(CS)
         skip
      end
   end

   class CodeGenAtomNode
      meth makeEquation(CS VO VHd VTl)
         VHd = vEquateLiteral(_ @value {VO reg($)} VTl)
      end
      meth makeRecordArgument(CS VHd VTl $)
         VHd = VTl
         literal(@value)
      end
      meth makeVO(CS VHd VTl ?VO)
         VO = {NewPseudoVariableOccurrence CS}
         VO.value = @value
         VHd = vEquateLiteral(_ @value {VO reg($)} VTl)
      end
      meth methPrintName($)
         @value
      end
   end

   class CodeGenIntNode
      meth makeEquation(CS VO VHd VTl)
         VHd = vEquateNumber(_ @value {VO reg($)} VTl)
      end
      meth makeRecordArgument(CS VHd VTl $)
         VHd = VTl
         number(@value)
      end
      meth makeVO(CS VHd VTl ?VO)
         VO = {NewPseudoVariableOccurrence CS}
         VO.value = @value
         VHd = vEquateNumber(_ @value {VO reg($)} VTl)
      end
   end

   class CodeGenFloatNode
      meth makeEquation(CS VO VHd VTl)
         VHd = vEquateNumber(_ @value {VO reg($)} VTl)
      end
      meth makeRecordArgument(CS VHd VTl $)
         VHd = VTl
         number(@value)
      end
      meth makeVO(CS VHd VTl ?VO)
         VO = {NewPseudoVariableOccurrence CS}
         VO.value = @value
         VHd = vEquateNumber(_ @value {VO reg($)} VTl)
      end
   end

   class CodeGenVariable
      attr reg
      meth setReg(CS)
         @reg = {CS newVariableReg(self $)}
      end
      meth setFreshReg(CS)
         reg <- {CS newVariableReg(self $)}
      end
      meth reg($)
         @reg
      end
   end

   class CodeGenVariableOccurrence
      meth getCodeGenValue($)
         case {IsDet @value} then
            case @value == self then _
            else {@value getCodeGenValue($)}
            end
         else _
         end
      end
      meth codeGenApplication(Designator Coord ActualArgs CS VHd VTl)
         {@value codeGenApplication(Designator Coord ActualArgs CS VHd VTl)}
      end
      meth reg($) Value = @value in
         case {IsDet Value}
            andthen {IsObject Value}
            andthen {HasFeature Value ImAVariableOccurrence}
         then Reg in
            {{Value getVariable($)} reg(?Reg)}
            % This variable occurrence may have been equated to a variable
            % occurrence invented by valToSubst.  Such occurrences are
            % assigned no registers, so we check for this case explicitly:
            case {IsDet Reg} then Reg
            else {@variable reg($)}
            end
         else {@variable reg($)}
         end
      end
      meth makeEquation(CS VO VHd VTl) Value in
         CodeGenVariableOccurrence, getCodeGenValue(?Value)
         case {IsDet Value} then
            case {IsNumber Value} then
               VHd = vEquateNumber(_ Value {{VO getVariable($)} reg($)} VTl)
            elsecase {IsLiteral Value} then
               VHd = vEquateLiteral(_ Value {{VO getVariable($)} reg($)} VTl)
            else skip
            end
         else skip
         end
         case {IsDet VHd} then skip
         else Value in
            {VO getCodeGenValue(?Value)}
            case {IsDet Value} then
               case {IsNumber Value} then
                  VHd = vEquateNumber(_ Value {@variable reg($)} VTl)
               elsecase {IsLiteral Value} then
                  VHd = vEquateLiteral(_ Value {@variable reg($)} VTl)
               else
                  {MakeUnify {@variable reg($)} {{VO getVariable($)} reg($)}
                   VHd VTl}
               end
            else
               {MakeUnify {@variable reg($)} {{VO getVariable($)} reg($)}
                VHd VTl}
            end
         end
         % If above just VO was used instead of {VO getVariable($)}, then
         % incorrect code would be generated:  The static analysis annotates
         % the occurrences to be equal, so a trivial (and wrong) vUnify(R R _)
         % would be generated.
      end
      meth makeRecordArgument(CS VHd VTl $) Value in
         VHd = VTl
         CodeGenVariableOccurrence, getCodeGenValue(?Value)
         case {IsDet Value} then
            case {IsNumber Value} then
               number(Value)
            elsecase {IsLiteral Value} then
               literal(Value)
            else
               value({@variable reg($)})
            end
         else
            value({@variable reg($)})
         end
      end
      meth makeVO(CS VHd VTl ?VO)
         VHd = VTl
         VO = self
      end
      meth isSwitchable($) Value in
         CodeGenVariableOccurrence, getCodeGenValue(?Value)
         {IsDet Value} andthen ({IsNumber Value} orelse {IsLiteral Value})
      end
      meth makeSwitchable(Reg LocalVars Body CS $)
         addScalar({self getCodeGenValue($)} LocalVars Body)
      end
      meth makeGetArg(CS PatternVs V1Hd V1Tl V2Hd V2Tl ?NewPatternVs) Reg VO in
         {CS newReg(?Reg)}
         V1Hd = vGetVariable(_ Reg V1Tl)
         VO = {New PseudoVariableOccurrence init(Reg)}
         {self makeEquation(CS VO V2Hd V2Tl)}
         NewPatternVs = PatternVs
      end
      meth methPrintName($)
         {@variable getPrintName($)}
      end
      meth addPatternVs(PatternVs ?NewPatternVs)
         NewPatternVs = PatternVs
      end
      meth assignRegToStructure(CS)
         skip
      end
   end

   class CodeGenPatternVariableOccurrence
      meth isSwitchable($)
         false
      end
      meth makeGetArg(CS PatternVs V1Hd V1Tl V2Hd V2Tl ?NewPatternVs)
         V1Hd = vGetVariable(_ {self reg($)} V1Tl)
         V2Hd = V2Tl
         CodeGenPatternVariableOccurrence,
         addPatternVs(PatternVs ?NewPatternVs)
      end
      meth addPatternVs(PatternVs ?NewPatternVs)
         case {Member @variable PatternVs} then
            NewPatternVs = PatternVs
         else
            NewPatternVs = @variable|PatternVs
         end
      end
      meth makeEquation(CS VO VHd VTl)
         {MakeUnify {@variable reg($)} {VO reg($)} VHd VTl}
      end
   end

   class CodeGenToken
      meth getCodeGenValue($)
         @value
      end
   end

   class CodeGenNameToken
      meth getCodeGenValue($)
         case @isToplevel then @value else _ end
      end
   end

   class CodeGenBuiltinToken
      meth codeGenApplication(Designator Coord ActualArgs CS VHd VTl)
         Builtinname = {System.printName @value}
         BIInfo = {Builtins.getInfo Builtinname}
      in
         case BIInfo == noInformation
            orelse {CondSelect BIInfo sited false}
         then
            VHd = vCall(_ {Designator reg($)}
                        {Map ActualArgs fun {$ Arg} {Arg reg($)} end}
                        Coord VTl)
         elsecase Builtinname of 'New' then
            [Arg1 Arg2 Arg3] = ActualArgs ObjReg Cont
         in
            % this ensures that the created object is always a fresh
            % register and that the message is sent before the new
            % object is unified with the output variable.  This is
            % needed for the correctness of the sendMsg-optimization
            % performed in the CodeEmitter:
            {CS newReg(?ObjReg)}
            VHd = vCallBuiltin(_ 'New' [{Arg1 reg($)} {Arg2 reg($)} ObjReg]
                               Coord Cont)
            Cont = vUnify(_ ObjReg {Arg3 reg($)} VTl)
         [] '+' then [Arg1 Arg2 Arg3] = ActualArgs Value in
            {Arg1 getCodeGenValue(?Value)}
            case {IsDet Value} then
               case Value of 1 then
                  VHd = vCallBuiltin(_ '+1' [{Arg2 reg($)} {Arg3 reg($)}]
                                     Coord VTl)
               [] ~1 then
                  VHd = vCallBuiltin(_ '-1' [{Arg2 reg($)} {Arg3 reg($)}]
                                     Coord VTl)
               else skip
               end
            else skip
            end
            case {IsDet VHd} then skip
            else Value in
               {Arg2 getCodeGenValue(?Value)}
               case {IsDet Value} then
                  case Value of 1 then
                     VHd = vCallBuiltin(_ '+1' [{Arg1 reg($)} {Arg3 reg($)}]
                                        Coord VTl)
                  [] ~1 then
                     VHd = vCallBuiltin(_ '-1' [{Arg1 reg($)} {Arg3 reg($)}]
                                        Coord VTl)
                  else skip
                  end
               else skip
               end
            end
         [] '-' then [Arg1 Arg2 Arg3] = ActualArgs Value in
            {Arg2 getCodeGenValue(?Value)}
            case {IsDet Value} then
               case Value of 1 then
                  VHd = vCallBuiltin(_ '-1' [{Arg1 reg($)} {Arg3 reg($)}]
                                     Coord VTl)
               [] ~1 then
                  VHd = vCallBuiltin(_ '+1' [{Arg1 reg($)} {Arg3 reg($)}]
                                     Coord VTl)
               else skip
               end
            else skip
            end
         elsecase CS.debugInfoControlSwitch then skip
         elsecase Builtinname of '.' then
            [Arg1 Arg2 Arg3] = ActualArgs Feature in
            {Arg2 getCodeGenValue(?Feature)}
            case {IsDet Feature} andthen {IsFeature Feature} then
               Value1 AlwaysSucceeds in
               {Arg1 getCodeGenValue(?Value1)}
               AlwaysSucceeds = ({IsDet Value1}
                                 andthen {IsRecord Value1}
                                 andthen {HasFeature Value1 Feature})
               case AlwaysSucceeds
                  andthen {IsObject Value1.Feature}
                  andthen {HasFeature Value1.Feature ImAVariableOccurrence}
                  andthen {IsDet {Value1.Feature reg($)}}
               then
                  % Evaluate by issuing an equation.
                  % Note: {Value1.Feature reg($)} may be undetermined for
                  % nested records annotated by valToSubst.
                  {Arg3 makeEquation(CS Value1.Feature VHd VTl)}
               else
                  % Because the static analyzer may annotate some
                  % variable equality at Arg3, we cannot use the
                  % (dereferencing) {Arg3 reg($)} call but have to
                  % use the variable's original register:
                  VHd = vInlineDot(_ {Arg1 reg($)} Feature
                                   {{Arg3 getVariable($)} reg($)}
                                   AlwaysSucceeds Coord VTl)
               end
            else skip
            end
         [] '@' then [Arg1 Arg2] = ActualArgs Atomname in
            {Arg1 getCodeGenValue(?Atomname)}
            case {IsDet Atomname} andthen {IsLiteral Atomname} then
               VHd = vInlineAt(_ Atomname {Arg2 reg($)} VTl)
            else skip
            end
         [] '<-' then [Arg1 Arg2] = ActualArgs Atomname in
            {Arg1 getCodeGenValue(?Atomname)}
            case {IsDet Atomname} andthen {IsLiteral Atomname} then
               VHd = vInlineAssign(_ Atomname {Arg2 reg($)} VTl)
            else skip
            end
         [] ',' then [Arg1 Arg2] = ActualArgs Value in
            {Arg2 getCodeGenValue(?Value)}
            case {IsDet Value} andthen {IsRecord Value} then
               RecordArity ActualArgs Regs Cont1 in
               case {IsTuple Value} then
                  RecordArity = {Width Value}
                  ActualArgs = {ForThread RecordArity 1 ~1
                                fun {$ In I} Value.I|In end nil}
               else
                  RecordArity = {Arity Value}
                  ActualArgs = {Map RecordArity fun {$ I} Value.I end}
               end
               {MakeMessageArgs ActualArgs CS ?Regs VHd Cont1}
               case {{Arg1 getVariable($)} isToplevel($)} then
                  Cont1 = vGenCall(_ {Arg1 reg($)} true
                                   {Label Value} RecordArity Regs
                                   Coord VTl)
               else
                  Cont1 = vApplMeth(_ {Arg1 reg($)}
                                    {Label Value} RecordArity Regs
                                    Coord VTl)
               end
            else skip
            end
         else skip
         end
         case {IsDet VHd} then skip
         else Regs in
            Regs = {Map ActualArgs fun {$ A} {A reg($)} end}
            VHd = vCallBuiltin(_ Builtinname Regs Coord VTl)
         end
      end
   end

   class CodeGenProcedureToken
      feat ClauseBodyShared
      meth codeGenApplication(Designator Coord ActualArgs CS VHd VTl) ID in
         ID = self.predicateRef
         case {IsDet ID} andthen ID \= unit then
            % ID may also be a real procedure
            VHd = vFastCall(_ ID {Map ActualArgs fun {$ A} {A reg($)} end}
                            Coord VTl)
         elsecase {IsDet self.clauseBodyStatements} then
            % this is the value produced by a ClauseBody node
            % (by construction, ActualArgs is nil)
            VHd = self.ClauseBodyShared
            VTl = nil
            case {IsFree VHd} then Label Count Addr in
               VHd = vShared(_ Label Count Addr)
               {CS newLabel(?Label)}
               Count = {NewCell 0}
               {CodeGenList self.clauseBodyStatements CS Addr nil}
            else skip
            end
         else
            VHd = vCall(_ {Designator reg($)}
                        {Map ActualArgs fun {$ A} {A reg($)} end} Coord VTl)
         end
      end
   end
end
