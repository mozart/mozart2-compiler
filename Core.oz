%%%
%%% Author:
%%%   Leif Kornstaedt <kornstae@ps.uni-sb.de>
%%%
%%% Contributors:
%%%   Martin Mueller (mmueller@ps.uni-sb.de)
%%%
%%% Copyright:
%%%   Leif Kornstaedt, 1997
%%%
%%% Last change:
%%%   $Date$ by $Author$
%%%   $Revision$
%%%
%%% This file is part of Mozart, an implementation of Oz 3:
%%%    http://mozart.ps.uni-sb.de
%%%
%%% See the file "LICENSE" or
%%%    http://mozart.ps.uni-sb.de/LICENSE.html
%%% for information on usage and redistribution
%%% of this file, and for a DISCLAIMER OF ALL
%%% WARRANTIES.
%%%

%%
%% General Notes:
%%
%% meth output(R ?FS)
%%    Only statement nodes have this method.  It produces a format
%%    string FS as defined by Gump.  The value of R indicates with
%%    which options to output:
%%       R.realcore     corresponds the switch realcore
%%       R.debugValue   output value attributes
%%       R.debugType    output variable types
%%
%% meth output2(R ?FS1 ?FS2)
%%    This corresponds to the above method, except that it is used
%%    for non-statement nodes.  FS2 is an additional format string
%%    to insert after the current statement.
%%

functor
import
   StaticAnalysis
   CodeGen
export
   FlattenSequence

   % names:
   ImAValueNode
   ImAVariableOccurrence
   ImAToken

   % abstract syntax:
   Statement
   TypeOf
   StepPoint
   Declaration
   SkipNode
   Equation
   Construction
   Definition
   FunctionDefinition
   ClauseBody
   Application
   BoolCase
   BoolClause
   PatternCase
   PatternClause
   RecordPattern
   EquationPattern
   AbstractElse
   ElseNode
   NoElse
   TryNode
   LockNode
   ClassNode
   Method
   MethodWithDesignator
   MethFormal
   MethFormalOptional
   MethFormalWithDefault
   ObjectLockNode
   GetSelf
   FailNode
   IfNode
   ChoicesAndDisjunctions
   OrNode
   DisNode
   ChoiceNode
   Clause
   ValueNode
   AtomNode
   IntNode
   FloatNode
   BitStringNode
   ByteStringNode
   Variable
   RestrictedVariable
   VariableOccurrence
   PatternVariableOccurrence

   % token representations:
   Token
   NameToken
   ProcedureToken
   ClauseBodyToken
   BuiltinToken
   CellToken
   ChunkToken
   ArrayToken
   DictionaryToken
   ClassToken
   ObjectToken
   LockToken
   PortToken
   ThreadToken
   SpaceToken
   BitArrayToken

define
   \insert Annotate

   %% some format strings auxiliaries for output
   IN = format(indent)
   EX = format(exdent)
   PU = format(push)
   PO = format(pop)
   GL = format(glue(" "))
   NL = format(break)
   fun {LI Xs Sep R}
      list({Map Xs fun {$ X} {X output(R $)} end} Sep)
   end
   fun {LI2 Xs Sep R ?FS}
      case Xs of X1|Xr then FS01 FS02 FSs in
	 {X1 output2(R ?FS01 ?FS02)}
	 FSs#FS = {FoldL Xr
		   fun {$ FSs#FS X} FS01 FS02 in
		      {X output2(R ?FS01 ?FS02)}
		      (FS01|FSs)#(FS#FS02)
		   end [FS01]#FS02}
	 list({Reverse FSs} Sep)
      [] nil then
	 FS = ""
	 ""
      end
   end

   fun {CheckOutput R Flagname}
      {CondSelect R Flagname false}
   end

   fun {OutputAttrFeat I R ?FS}
      case I of F#T then FS1 FS2 in
	 FS = FS1#FS2
	 {F outputEscaped2(R $ ?FS1)}#': '#{T output2(R $ ?FS2)}
      else
	 {I outputEscaped2(R $ ?FS)}
      end
   end

   fun {FilterUnitsToVS Xs}
      case Xs of X|Xr then
	 case X of unit then {FilterUnitsToVS Xr}
	 else X#{FilterUnitsToVS Xr}
	 end
      [] nil then ""
      end
   end

   local
      proc {FlattenSequenceSub X Hd Tl}
	 % This procedure converts a statement sequence represented
	 % using '|' as a pair constructor, whose left and/or right
	 % element may also be a pair, into a list.
	 case X of S1|S2 then Inter in
	    {FlattenSequenceSub S1 Hd Inter}
	    {FlattenSequenceSub S2 Inter Tl}
	 [] nil then
	    Hd = Tl
	 else
	    if {X isRedundant($)} then
	       Hd = Tl
	    else
	       Hd = X|Tl
	    end
	 end
      end

      fun {GetFirst X}
	 case X of S1|S2 then First in
	    First = {GetFirst S1}
	    case First of nil then {GetFirst S2}
	    else First
	    end
	 [] nil then nil
	 else X
	 end
      end

      fun {SetPointers Prev Next}
	 {Prev setNext(Next)}
	 Next
      end

      proc {LinkList First|Rest} Last in
	 Last = {FoldL Rest SetPointers First}
	 {Last setNext(Last)}   % termination
      end
   in
      proc {FlattenSequence X ?Res} Hd in
	 {FlattenSequenceSub X Hd nil}
	 Res = case Hd of nil then First in
		  First = {GetFirst X}
		  case First of nil then [{New SkipNode init(unit)}]
		  else [First]
		  end
	       else Hd
	       end
	 {LinkList Res}
      end
   end

   ImAValueNode          = StaticAnalysis.imAValueNode
   ImAVariableOccurrence = StaticAnalysis.imAVariableOccurrence
   ImAToken              = StaticAnalysis.imAToken

   class Statement
      from Annotate.statement StaticAnalysis.statement CodeGen.statement
      attr next: unit coord: unit
      meth setPrintName(_)
	 skip
      end
      meth isRedundant($)
	 false
      end
      meth setNext(S)
	 next <- S
      end
      meth getCoord($)
	 @coord
      end
   end

   class TypeOf
      from Statement Annotate.typeOf StaticAnalysis.typeOf CodeGen.typeOf
      attr arg: unit res: unit value: unit
      meth init(Arg Res)
	 arg <- Arg
	 res <- Res
	 value <- type([value])
      end
      meth output(R $) FS in
	 {@res output2(R $ ?FS)}#' = '#
	 {Value.toVirtualString @value 50 1000}#
	 '   % typeof '#{@arg output(R $)}#FS
      end
   end

   class StepPoint
      from Statement Annotate.stepPoint StaticAnalysis.stepPoint
	 CodeGen.stepPoint
      prop final
      attr statements: unit kind: unit
      meth init(Statements Kind Coord)
	 statements <- {FlattenSequence Statements}
	 kind <- Kind
	 coord <- Coord
      end
      meth output(R $)
	 {LI @statements NL R}
      end
   end

   class Declaration
      from Statement Annotate.declaration StaticAnalysis.declaration
	 CodeGen.declaration
      prop final
      attr localVars: unit statements: unit
      meth init(LocalVars Statements Coord)
	 localVars <- LocalVars
	 statements <- {FlattenSequence Statements}
	 coord <- Coord
      end
      meth output(R $)
	 'local'#GL#IN#{LI @localVars GL true}#EX#GL#'in'#IN#NL#
	 {LI @statements NL R}#EX#NL#'end'
      end
   end

   class SkipNode
      from Statement Annotate.skipNode CodeGen.skipNode
      prop final
      meth init(Coord)
	 coord <- Coord
      end
      meth isRedundant($)
	 true
      end
      meth output(_ $)
	 'skip skip'
      end
   end

   class Equation
      from Statement Annotate.equation StaticAnalysis.equation CodeGen.equation
      prop final
      attr left: unit right: unit
      meth init(Left Right Coord)
	 left <- Left
	 right <- Right
	 coord <- Coord
      end
      meth output(R $) FS1 FS2 in
	 {@left output2(R $ ?FS1)}#' = '#{@right output2(R $ ?FS2)}#FS1#FS2
      end
   end

   class Construction
      from Annotate.construction StaticAnalysis.construction
	 CodeGen.construction
      prop final
      attr label: unit args: unit isOpen: unit
      meth init(Label Args IsOpen)
	 label <- Label
	 args <- Args
	 isOpen <- IsOpen
	 StaticAnalysis.construction, init()
      end
      meth getCoord($)
	 {@label getCoord($)}
      end
      meth output2(R $ ?FS) FS1 FS2 in
	 FS = FS1#FS2
	 {@label output2(R $ ?FS1)}#'('#PU#
	 case @args of X1|Xr then Start FSs in
	    case X1 of F#T then FS01 FS02 FS11 FS12 in
	       {F output2(R ?FS01 ?FS02)}
	       {T output2(R ?FS11 ?FS12)}
	       Start = [FS01#': '#FS11]#(FS02#FS12)
	    else FS01 FS02 in
	       {X1 output2(R ?FS01 ?FS02)}
	       Start = [FS01]#FS02
	    end
	    FSs#FS2 = {FoldL Xr
		       fun {$ FSs#FS X}
			  case X of F#T then FS01 FS02 FS11 FS12 in
			     {F output2(R ?FS01 ?FS02)}
			     {T output2(R ?FS11 ?FS12)}
			     (FS01#': '#FS11|FSs)#(FS#FS02#FS12)
			  else FS01 FS02 in
			     {X output2(R ?FS01 ?FS02)}
			     (FS01|FSs)#(FS#FS02)
			  end
		       end Start}
	    list({Reverse FSs} GL)
	 else
	    FS2 = ""
	    ""
	 end#
	 if @isOpen then
	    case @args of nil then '...' else GL#'...' end
	 else ""
	 end#')'#PO
      end
      meth isConstruction($)
	 true
      end
   end

   class Definition
      from Statement Annotate.definition StaticAnalysis.definition
	 CodeGen.definition
      attr
	 designator: unit formalArgs: unit statements: unit
	 isStateUsing: unit procFlags: unit printName: '' toCopy: unit
	 allVariables: nil predicateRef: unit
      meth init(Designator FormalArgs Statements IsStateUsing ProcFlags
		Coord)
	 designator <- Designator
	 formalArgs <- FormalArgs
	 statements <- {FlattenSequence Statements}
	 isStateUsing <- IsStateUsing
	 procFlags <- ProcFlags
	 coord <- Coord
      end
      meth setAllVariables(Vs)
	 allVariables <- Vs
      end
      meth setPrintName(PrintName)
	 printName <- PrintName
      end
      meth output(R $) FS1 in
	 {FoldL @procFlags
	  fun {$ In A} In#{Value.toVirtualString A 0 0}#' ' end
	  'proc '}#
	 '{'#PU#{@designator output2(R $ ?FS1)}#
	 case @formalArgs of _|_ then GL#{LI @formalArgs GL R}
	 [] nil then ""
	 end#'}'#
	 if {self isClauseBody($)} then '   % clause body' else "" end#
	 PO#IN#FS1#NL#
	 {LI @statements NL R}#EX#NL#'end'
      end
      meth isClauseBody($)
	 false
      end
   end
   class FunctionDefinition
      from Definition Annotate.functionDefinition CodeGen.functionDefinition
      prop final
   end
   class ClauseBody
      from Definition Annotate.clauseBody CodeGen.clauseBody
      prop final
      meth isClauseBody($)
	 true
      end
   end

   class Application
      from Statement Annotate.application StaticAnalysis.application
	 CodeGen.application
      prop final
      attr designator: unit actualArgs: unit
      feat codeGenMakeEquateLiteral
      meth init(Designator ActualArgs Coord)
	 designator <- Designator
	 actualArgs <- ActualArgs
	 coord <- Coord
      end
      meth output(R $)
	 if {CheckOutput R realcore} then
	    Application, OutputApplication(R $)
	 else P = {{@designator getVariable($)} getPrintName($)} in
	    case P of '`ooExch`' then Attr New Old FS1 FS2 FS3 in
	       @actualArgs = [Attr New Old]
	       {Old output2(R $ ?FS1)}#' = '#
	       {Attr output2(R $ ?FS2)}#' <- '#{New output2(R $ ?FS3)}#
	       FS1#FS2#FS3
	    [] '`@`' then Application, OutputPrefixExpression('@' R $)
	    [] '`~`' then Application, OutputPrefixExpression('~' R $)
	    [] '`<-`' then Application, OutputInfixStatement(' <- ' R $)
	    [] '`,`' then Application, OutputInfixStatement(', ' R $)
	    [] '`==`' then Application, OutputInfixExpression(' == ' R $)
	    [] '`<`' then Application, OutputInfixExpression(' < ' R $)
	    [] '`>`' then Application, OutputInfixExpression(' > ' R $)
	    [] '`=<`' then Application, OutputInfixExpression(' =< ' R $)
	    [] '`>=`' then Application, OutputInfixExpression(' >= ' R $)
	    [] '`\\=`' then Application, OutputInfixExpression(' \\= ' R $)
	    [] '`div`' then Application, OutputInfixExpression(' div ' R $)
	    [] '`mod`' then Application, OutputInfixExpression(' mod ' R $)
	    [] '`+`' then Application, OutputInfixExpression(' + ' R $)
	    [] '`-`' then Application, OutputInfixExpression(' - ' R $)
	    [] '`*`' then Application, OutputInfixExpression(' * ' R $)
	    [] '`/`' then Application, OutputInfixExpression(' / ' R $)
	    [] '`.`' then Application, OutputInfixExpression('.' R $)
	    [] '`^`' then Application, OutputInfixExpression('^' R $)
	    [] '`::`' then Application, OutputFdInStatement(' :: ' R $)
	    [] '`:::`' then Application, OutputFdInStatement(' ::: ' R $)
	    [] '`::R`' then Application, OutputFdInExpression(' :: ' R $)
	    [] '`:::R`' then Application, OutputFdInExpression(' ::: ' R $)
	    [] '`Raise`' then E FS in
	       @actualArgs = [E]
	       'raise '#{E output2(R $ ?FS)}#' end'#FS
	    else
	       Application, OutputApplication(R $)
	    end
	 end
      end
      meth OutputApplication(R $) FS1 FS2 in
	 '{'#PU#{@designator output2(R $ ?FS1)}#
	 case @actualArgs of _|_ then GL#{LI2 @actualArgs GL R ?FS2}
	 [] nil then FS2 = "" ""
	 end#'}'#PO#FS1#FS2
      end
      meth OutputPrefixExpression(Op R $) E1 E2 FS1 FS2 in
	 @actualArgs = [E1 E2]
	 {E2 output2(R $ ?FS1)}#' = '#Op#{E1 output2(R $ ?FS2)}#FS1#FS2
      end
      meth OutputInfixStatement(Op R $) E1 E2 FS1 FS2 in
	 @actualArgs = [E1 E2]
	 {E1 output2(R $ ?FS1)}#Op#{E2 output2(R $ ?FS2)}#FS1#FS2
      end
      meth OutputInfixExpression(Op R $) E1 E2 E3 FS1 FS2 FS3 in
	 @actualArgs = [E1 E2 E3]
	 {E3 output2(R $ ?FS1)}#' = '#
	 {E1 output2(R $ ?FS2)}#Op#{E2 output2(R $ ?FS3)}#FS1#FS2#FS3
      end
      meth OutputFdInStatement(Op R $) E1 E2 FS1 FS2 in
	 @actualArgs = [E1 E2]
	 {E2 output2(R $ ?FS1)}#Op#{E1 output2(R $ ?FS2)}#FS1#FS2
      end
      meth OutputFdInExpression(Op R $) E1 E2 E3 FS1 FS2 FS3 in
	 @actualArgs = [E1 E2 E3]
	 {E3 output2(R $ ?FS1)}#' = '#
	 {E2 output2(R $ ?FS2)}#Op#{E1 output2(R $ ?FS3)}#FS1#FS2#FS3
      end
   end

   class BoolCase
      from Statement Annotate.boolCase StaticAnalysis.boolCase CodeGen.boolCase
      prop final
      attr arbiter: unit consequent: unit alternative: unit
      feat noBoolShared
      meth init(Arbiter Consequent Alternative Coord)
	 arbiter <- Arbiter
	 consequent <- Consequent
	 alternative <- Alternative
	 coord <- Coord
      end
      meth output(R $) FS in
	 'if '#{@arbiter output2(R $ ?FS)}#' then'#IN#NL#
	 {@consequent output(R $)}#EX#NL#{@alternative output(R $)}#'end'#FS
      end
   end

   class BoolClause
      from Annotate.boolClause StaticAnalysis.boolClause CodeGen.boolClause
      prop final
      attr statements: unit
      meth init(Statements)
	 statements <- {FlattenSequence Statements}
      end
      meth output(R $)
	 {LI @statements NL R}
      end
   end

   class PatternCase
      from Statement Annotate.patternCase StaticAnalysis.patternCase
	 CodeGen.patternCase
      prop final
      attr arbiter: unit clauses: unit alternative: unit
      meth init(Arbiter Clauses Alternative Coord)
	 arbiter <- Arbiter
	 clauses <- Clauses
	 alternative <- Alternative
	 coord <- Coord
      end
      meth output(R $) FS in
	 'case '#{@arbiter output2(R $ ?FS)}#' of '#
	 {LI @clauses NL#'[] ' R}#NL#
	 {@alternative output(R $)}#'end'#FS
      end
   end

   class PatternClause
      from Annotate.patternClause StaticAnalysis.patternClause
	 CodeGen.patternClause
      prop final
      attr localVars: unit pattern: unit statements: unit
      meth init(LocalVars Pattern Statements)
	 localVars <- LocalVars
	 pattern <- Pattern
	 statements <- {FlattenSequence Statements}
      end
      meth output(R $) FS in
	 PU#{@pattern outputPattern2(R @localVars $ ?FS)}#PO#GL#'then'#IN#
	 FS#NL#{LI @statements NL R}#EX
      end
   end

   class RecordPattern
      from Annotate.recordPattern StaticAnalysis.recordPattern
	 CodeGen.recordPattern
      prop final
      attr label: unit args: unit isOpen: unit
      meth init(Label Args IsOpen)
	 label <- Label
	 args <- Args
	 isOpen <- IsOpen
	 StaticAnalysis.recordPattern, init()
      end
      meth getCoord($)
	 {@label getCoord($)}
      end
      meth output2(R $ ?FS) FS1 FS2 Args in
	 FS = FS1#FS2
	 case @args of X1|Xr then Start FSs in
	    case X1 of F#P then FS01 FS02 FS11 FS12 in
	       {F output2(R ?FS01 ?FS02)}
	       {P output2(R ?FS11 ?FS12)}
	       Start = [FS01#': '#FS11]#(FS02#FS12)
	    else FS01 FS02 in
	       {X1 output2(R ?FS01 ?FS02)}
	       Start = [FS01]#FS02
	    end
	    FSs#FS2 = {FoldL Xr
		       fun {$ FSs#FS X}
			  case X of F#P then FS01 FS02 FS11 FS12 in
			     {F output2(R ?FS01 ?FS02)}
			     {P output2(R ?FS11 ?FS12)}
			     (FS01#': '#FS11|FSs)#(FS#FS02#FS12)
			  else FS01 FS02 in
			     {X output2(R ?FS01 ?FS02)}
			     (FS01|FSs)#(FS#FS02)
			  end
		       end Start}
	    Args = list({Reverse FSs} GL)
	 else
	    FS2 = ""
	    Args = ""
	 end
	 {@label output2(R $ ?FS1)}#'('#PU#Args#
	 if @isOpen then
	    case Args of nil then '...' else GL#'...' end
	 else ""
	 end#')'#PO
      end
      meth outputPattern2(R Vs $ ?FS) FS1 FS2 Args in
	 FS = FS1#FS2
	 case @args of X1|Xr then Start FSs in
	    case X1 of F#P then FS01 FS02 FS11 FS12 in
	       {F output2(R ?FS01 ?FS02)}
	       {P outputPattern2(R Vs ?FS11 ?FS12)}
	       Start = [FS01#': '#FS11]#(FS02#FS12)
	    else FS01 FS02 in
	       {X1 outputPattern2(R Vs ?FS01 ?FS02)}
	       Start = [FS01]#FS02
	    end
	    FSs#FS2 = {FoldL Xr
		       fun {$ FSs#FS Arg}
			  case Arg of F#P then FS01 FS02 FS11 FS12 in
			     {F output2(R ?FS01 ?FS02)}
			     {P outputPattern2(R Vs ?FS11 ?FS12)}
			     (FS01#': '#FS11|FSs)#(FS#FS02#FS12)
			  else FS01 FS02 in
			     {Arg outputPattern2(R Vs ?FS01 ?FS02)}
			     (FS01|FSs)#(FS#FS02)
			  end
		       end Start}
	    Args = list({Reverse FSs} GL)
	 else
	    FS2 = ""
	    Args = ""
	 end
	 {@label output2(R $ ?FS1)}#'('#PU#Args#
	 if @isOpen then
	    case Args of nil then '...' else GL#'...' end
	 else ""
	 end#')'#PO
      end
      meth isConstruction($)
	 true
      end
   end

   class EquationPattern
      from Annotate.equationPattern StaticAnalysis.equationPattern
	 CodeGen.equationPattern
      prop final
      attr left: unit right: unit coord: unit
      meth init(Left Right Coord)
	 left <- Left
	 right <- Right
	 coord <- Coord
      end
      meth getCoord($)
	 @coord
      end
      meth output2(R $ ?FS) FS1 FS2 in
	 FS = FS1#FS2
	 {@left output2(R $ ?FS1)}#'='#{@right output2(R $ ?FS2)}
      end
      meth outputPattern2(R Vs $ ?FS) FS1 FS2 in
	 FS = FS1#FS2
	 {@left outputPattern2(R Vs $ ?FS1)}#'='#
	 {@right outputPattern2(R Vs $ ?FS2)}
      end
      meth isConstruction($)
	 {@right isConstruction($)}
      end
   end

   class AbstractElse
      from Annotate.abstractElse CodeGen.abstractElse
   end
   class ElseNode
      from AbstractElse Annotate.elseNode StaticAnalysis.elseNode
	 CodeGen.elseNode
      prop final
      attr statements: unit
      meth init(Statements)
	 statements <- {FlattenSequence Statements}
      end
      meth output(R $)
	 'else'#IN#NL#
	 {LI @statements NL R}#EX#NL
      end
   end
   class NoElse
      from AbstractElse Annotate.noElse StaticAnalysis.noElse CodeGen.noElse
      prop final
      attr coord: unit
      meth init(Coord)
	 coord <- Coord
      end
      meth getCoord($)
	 @coord
      end
      meth output(_ $)
	 ""
      end
   end

   class TryNode
      from Statement Annotate.tryNode StaticAnalysis.tryNode CodeGen.tryNode
      prop final
      attr tryStatements: unit exception: unit catchStatements: unit
      meth init(TryStatements Exception CatchStatements Coord)
	 tryStatements <- {FlattenSequence TryStatements}
	 exception <- Exception
	 catchStatements <- {FlattenSequence CatchStatements}
	 coord <- Coord
      end
      meth output(R $)
	 'try'#IN#NL#
	 {LI @tryStatements NL R}#EX#NL#
	 'catch '#{@exception output(R $)}#' then'#
	 IN#NL#{LI @catchStatements NL R}#EX#NL#'end'
      end
   end

   class LockNode
      from Statement Annotate.lockNode StaticAnalysis.lockNode CodeGen.lockNode
      prop final
      attr lockVar: unit statements: unit
      meth init(LockVar Statements Coord)
	 lockVar <- LockVar
	 statements <- {FlattenSequence Statements}
	 coord <- Coord
      end
      meth output(R $) FS in
	 'lock '#{@lockVar output2(R $ ?FS)}#' then'#IN#NL#
	 {LI @statements NL R}#EX#NL#'end'#FS
      end
   end

   class ClassNode
      from Statement Annotate.classNode StaticAnalysis.classNode
	 CodeGen.classNode
      prop final
      attr
	 designator: unit parents: unit properties: unit
	 attributes: unit features: unit methods: unit
	 printName: '' isToplevel: false
      meth init(Designator Parents Props Attrs Feats Meths Coord)
	 designator <- Designator
	 parents <- Parents
	 properties <- Props
	 attributes <- Attrs
	 features <- Feats
	 methods <- Meths
	 coord <- Coord
      end
      meth setPrintName(PrintName)
	 printName <- PrintName
      end
      meth output(R $) FS1 in
	 'class '#{@designator output2(R $ ?FS1)}#IN#FS1#
	 if @parents \= nil
	    orelse @properties \= nil
	    orelse @attributes \= nil
	    orelse @features \= nil
	    orelse @methods \= nil
	 then NL
	 else ""
	 end#
	 case @parents of _|_ then FS2 in
	    PU#'from'#GL#{LI2 @parents GL R ?FS2}#PO#FS2#
	    if @properties \= nil
	       orelse @attributes \= nil
	       orelse @features \= nil
	       orelse @methods \= nil
	    then NL
	    else ""
	    end
	 else ""
	 end#
	 case @properties of _|_ then FS3 in
	    PU#'prop'#GL#{LI2 @properties GL R ?FS3}#PO#FS3#
	    if @attributes \= nil
	       orelse @features \= nil
	       orelse @methods \= nil
	    then NL
	    else ""
	    end
	 else ""
	 end#
	 case @attributes of A1|Ar then FS0 FS1 FSs FS4 in
	    FS1 = {OutputAttrFeat A1 R ?FS0}
	    FSs#FS4 = {FoldL Ar
		       fun {$ FSs#FS I} FS0 in
			  ({OutputAttrFeat I R ?FS0}|FSs)#(FS#FS0)
		       end [FS1]#FS0}
	    PU#'attr'#GL#list({Reverse FSs} GL)#PO#FS4#
	    if @features \= nil orelse @methods \= nil then NL else "" end
	 else ""
	 end#
	 case @features of F1|Fr then FS0 FS1 FSs FS5 in
	    FS1 = {OutputAttrFeat F1 R ?FS0}
	    FSs#FS5 = {FoldL Fr
		       fun {$ FSs#FS I} FS0 in
			  ({OutputAttrFeat I R ?FS0}|FSs)#(FS#FS0)
		       end [FS1]#FS0}
	    PU#'feat'#GL#list({Reverse FSs} GL)#PO#FS5#
	    if @methods \= nil then NL else "" end
	 else ""
	 end#{LI @methods NL R}#EX#NL#'end'
      end
   end

   class Method
      from Annotate.method StaticAnalysis.method CodeGen.method
      attr
	 label: unit formalArgs: unit statements: unit coord: unit
	 allVariables: nil predicateRef: unit
      meth init(Label FormalArgs Statements Coord)
	 label <- Label
	 formalArgs <- FormalArgs
	 statements <- {FlattenSequence Statements}
	 coord <- Coord
      end
      meth setAllVariables(Vs)
	 allVariables <- Vs
      end
      meth getCoord($)
	 @coord
      end
      meth output(R $) FS1 FS2 in
	 'meth '#{@label outputEscaped2(R $ ?FS1)}#'('#PU#
	 {LI2 @formalArgs GL R ?FS2}#')'#PO#IN#FS1#FS2#NL#
	 {LI @statements NL R}#EX#NL#'end'
      end
   end
   class MethodWithDesignator
      from Method Annotate.methodWithDesignator
	 StaticAnalysis.methodWithDesignator CodeGen.methodWithDesignator
      prop final
      attr messageDesignator: unit isOpen: unit
      meth init(Label FormalArgs IsOpen MessageDesignator Statements Coord)
	 Method, init(Label FormalArgs Statements Coord)
	 isOpen <- IsOpen
	 messageDesignator <- MessageDesignator
      end
      meth output(R $) FS1 FS2 in
	 'meth '#{@label outputEscaped2(R $ ?FS1)}#'('#PU#
	 {LI2 @formalArgs GL R ?FS2}#
	 if @isOpen then
	    case @formalArgs of nil then '...' else GL#'...' end
	 else ""
	 end#') = '#{@messageDesignator output(R $)}#PO#IN#FS1#FS2#NL#
	 {LI @statements NL R}#EX#NL#'end'
      end
   end

   class MethFormal
      from Annotate.methFormal StaticAnalysis.methFormal CodeGen.methFormal
      attr feature: unit arg: unit
      meth init(Feature Arg)
	 feature <- Feature
	 arg <- Arg
      end
      meth getFeature($)
	 @feature
      end
      meth getVariable($)
	 @arg
      end
      meth hasDefault($)
	 false
      end
      meth output2(R $ ?FS)
	 {@feature output2(R $ ?FS)}#': '#{@arg output(R $)}
      end
   end
   class MethFormalOptional
      from MethFormal Annotate.methFormalOptional
	 StaticAnalysis.methFormalOptional CodeGen.methFormalOptional
      prop final
      attr isInitialized: unit
      meth init(Feature Arg IsInitialized)
	 feature <- Feature
	 arg <- Arg
	 isInitialized <- IsInitialized
      end
      meth hasDefault($)
	 true
      end
      meth output2(R $ ?FS)
	 MethFormal, output2(R $ ?FS)#' <= _'
      end
   end
   class MethFormalWithDefault
      from MethFormal Annotate.methFormalWithDefault
	 StaticAnalysis.methFormalWithDefault CodeGen.methFormalWithDefault
      prop final
      attr default: unit
      meth init(Feature Arg Default)
	 MethFormal, init(Feature Arg)
	 default <- Default
      end
      meth hasDefault($)
	 true
      end
      meth output2(R $ ?FS)
	 MethFormal, output2(R $ ?FS)#' <= '#
	 {Value.toVirtualString @default 50 1000}
      end
   end

   class ObjectLockNode
      from Statement Annotate.objectLockNode StaticAnalysis.objectLockNode
	 CodeGen.objectLockNode
      prop final
      attr statements: unit
      meth init(Statements Coord)
	 statements <- {FlattenSequence Statements}
	 coord <- Coord
      end
      meth output(R $)
	 'lock'#IN#NL#{LI @statements NL R}#EX#NL#'end'
      end
   end

   class GetSelf
      from Statement Annotate.getSelf StaticAnalysis.getSelf CodeGen.getSelf
      prop final
      attr destination: unit
      meth init(Destination Coord)
	 destination <- Destination
	 coord <- Coord
      end
      meth output(R $) FS in
	 {@destination output2(R $ ?FS)}#' = self'#FS
      end
   end

   class FailNode
      from Statement Annotate.failNode CodeGen.failNode
      prop final
      meth init(Coord)
	 coord <- Coord
      end
      meth output(_ $)
	 'fail'
      end
   end

   class IfNode
      from Statement Annotate.ifNode StaticAnalysis.ifNode CodeGen.ifNode
      prop final
      attr clauses: unit alternative: unit
      meth init(Clauses Alternative Coord)
	 clauses <- Clauses
	 alternative <- Alternative
	 coord <- Coord
      end
      meth output(R $)
	 'cond '#IN#{LI @clauses EX#NL#'[] '#IN R}#EX#NL#
	 {@alternative output(R $)}#'end'
      end
   end

   class ChoicesAndDisjunctions
      from Statement Annotate.choicesAndDisjunctions
	 StaticAnalysis.choicesAndDisjunctions CodeGen.choicesAndDisjunctions
      attr clauses: unit
      meth init(Clauses Coord)
	 clauses <- Clauses
	 coord <- Coord
      end
   end
   class OrNode
      from ChoicesAndDisjunctions Annotate.orNode CodeGen.orNode
      prop final
      meth output(R $)
	 'or '#IN#{LI @clauses EX#NL#'[] '#IN R}#EX#NL#'end'
      end
   end
   class DisNode
      from ChoicesAndDisjunctions Annotate.disNode CodeGen.disNode
      prop final
      meth output(R $)
	 'dis '#IN#{LI @clauses EX#NL#'[] '#IN R}#EX#NL#'end'
      end
   end
   class ChoiceNode
      from ChoicesAndDisjunctions Annotate.choiceNode CodeGen.choiceNode
      prop final
      meth output(R $)
	 'choice '#IN#{LI @clauses EX#NL#'[] '#IN R}#EX#NL#'end'
      end
   end

   class Clause
      from Annotate.clause StaticAnalysis.clause CodeGen.clause
      prop final
      attr localVars: unit guard: unit kind: unit statements: unit
      meth init(LocalVars Guard Kind Statements)
	 localVars <- LocalVars
	 guard <- {FlattenSequence Guard}
	 kind <- Kind
	 statements <- {FlattenSequence Statements}
      end
      meth output(R $)
	 case @localVars of _|_ then
	    {LI @localVars GL R}#EX#GL#'in'#IN#NL
	 [] nil then ""
	 end#{LI @guard NL R}#EX#NL#'then'#IN#NL#
	 case @kind of waitTop then 'skip   % top commit'
	 else {LI @statements NL R}
	 end
      end
   end

   class ValueNode
      from Annotate.valueNode StaticAnalysis.valueNode CodeGen.valueNode
      attr value: unit coord: unit
      feat !ImAValueNode: unit
      meth init(Value Coord)
	 value <- Value
	 coord <- Coord
	 StaticAnalysis.valueNode, init()
      end
      meth getCoord($)
	 @coord
      end
      meth getValue($)
	 @value
      end
      meth isConstruction($)
	 false
      end
      meth outputEscaped2(R $ ?FS)
	 {self output2(R $ ?FS)}
      end
   end

   class AtomNode
      from ValueNode Annotate.atomNode CodeGen.atomNode
      prop final
      meth output2(_ $ ?FS)
	 FS = ""
	 {Value.toVirtualString @value 0 0}
      end
      meth outputPattern2(_ _ $ ?FS)
	 FS = ""
	 {Value.toVirtualString @value 0 0}
      end
   end

   class IntNode
      from ValueNode Annotate.intNode CodeGen.intNode
      prop final
      meth output2(_ $ ?FS)
	 FS = ""
	 if @value < 0 then '~'#~@value else @value end
      end
      meth outputPattern2(_ _ $ ?FS)
	 FS = ""
	 if @value < 0 then '~'#~@value else @value end
      end
   end

   class FloatNode
      from ValueNode Annotate.floatNode CodeGen.floatNode
      prop final
      meth output2(_ $ ?FS)
	 FS = ""
	 if @value < 0.0 then '~'#~@value else @value end
      end
      meth outputPattern2(_ _ $ ?FS)
	 FS = ""
	 if @value < 0.0 then '~'#~@value else @value end
      end
   end

   class BitStringNode from ValueNode
      prop final
      feat kind: 'bitString'
   end

   class ByteStringNode from ValueNode
      prop final
      feat kind: 'byteString'
   end

   class Variable
      from Annotate.variable StaticAnalysis.variable CodeGen.variable
      attr printName: unit origin: unit coord: unit isToplevel: false
      meth init(PrintName Origin Coord)
	 printName <- PrintName
	 origin <- Origin
	 coord <- Coord
	 StaticAnalysis.variable, init()
      end
      meth isRestricted($)
	 false
      end
      meth isDenied(Feature ?GV $)
	 GV = unit
	 false
      end
      meth getPrintName($)
	 @printName
      end
      meth getOrigin($)
	 @origin
      end
      meth getCoord($)
	 @coord
      end
      meth setToplevel(T)
	 isToplevel <- T
      end
      meth isToplevel($)
	 @isToplevel
      end
      meth occ(Coord ?VO)
	 VO = {New VariableOccurrence init(self Coord)}
      end
      meth output(R $)
	 pn(@printName)
      end
      meth outputEscaped(R $)
	 '!'#pn(@printName)
      end
      meth outputPattern(R Vs $) PrintName = @printName in
	 if {Some Vs fun {$ V} {V getPrintName($)} == PrintName end} then
	    Variable, output(R $)
	 else
	    Variable, outputEscaped(R $)
	 end
      end
   end

   class RestrictedVariable
      from Variable Annotate.restrictedVariable
      prop final
      attr features: unit
      meth init(PrintName Features Coord)
	 Variable, init(PrintName user Coord)
	 features <- Features
      end
      meth isRestricted($)
	 @features \= nil
      end
      meth isDenied(Feature ?GV $) Fs = @features in
	 case Fs of nil then
	    GV = unit
	    false
	 else
	    RestrictedVariable, IsDenied(Fs Feature ?GV $)
	 end
      end
      meth IsDenied(Fs Feature ?GV $)
	 case Fs of X|Fr then
	    if Feature == X.1 then
	       X.3 = true
	       GV = case X of _#_#_#GV0 then GV0
		    else unit
		    end
	       false
	    else
	       RestrictedVariable, IsDenied(Fr Feature ?GV $)
	    end
	 [] nil then
	    GV = unit
	    true
	 end
      end
   end

   class VariableOccurrence
      from Annotate.variableOccurrence StaticAnalysis.variableOccurrence
	 CodeGen.variableOccurrence
      attr variable: unit coord: unit value: unit
      feat !ImAVariableOccurrence: unit
      meth init(Variable Coord)
	 variable <- Variable
	 coord <- Coord
	 value <- self
      end
      meth getCoord($)
	 @coord
      end
      meth getValue($)
	 @value
      end
      meth setValue(Value)
	 value <- Value
      end
      meth isConstruction($)
	 false
      end
      meth makeIntoPatternVariableOccurrence($)
	 {New PatternVariableOccurrence init(@variable @coord)}
      end
      meth getVariable($)
	 @variable
      end
      meth output2(R $ ?FS)
	 VariableOccurrence, OutputValue(R ?FS)
	 {@variable output(R $)}
      end
      meth outputEscaped2(R $ ?FS)
	 VariableOccurrence, OutputValue(R ?FS)
	 {@variable outputEscaped(R $)}
      end
      meth outputPattern2(R Vs $ ?FS)
	 VariableOccurrence, OutputValue(R ?FS)
	 {@variable outputPattern(R Vs $)}
      end
      meth OutputValue(R $)
	 DebugOutputs =
	 {FilterUnitsToVS
	  if {CheckOutput R debugValue} then
	     NL#'%    value: '#
	     StaticAnalysis.variableOccurrence, outputDebugValue($)
	  else unit
	  end|
	  if {CheckOutput R debugType} then
	     [NL#'%    type: '#{@variable outputDebugType($)}
	      case {@variable outputDebugProps($)} of unit then unit
	      elseof Ps then
		 NL#'%    prop: '#{Value.toVirtualString Ps 10 10}
	      end
	      case {@variable outputDebugAttrs($)} of unit then unit
	      elseof As then
		 NL#'%    attr: '#{Value.toVirtualString As 10 10}
	      end
	      case {@variable outputDebugFeats($)} of unit then unit
	      elseof Fs then
		 NL#'%    feat: '#{Value.toVirtualString Fs 10 10}
	      end
	      case {@variable outputDebugMeths($)} of unit then unit
	      elseof Ms then
		 NL#'%    meth: '#{Value.toVirtualString Ms 10 10}
	      end]
	  else nil
	  end}
      in
	 case DebugOutputs of nil then ""
	 else
	    NL#'% '#{@variable output(debug(realcore: true) $)}#':'#
	    DebugOutputs
	 end
      end
   end

   class PatternVariableOccurrence
      from VariableOccurrence Annotate.patternVariableOccurrence
	 CodeGen.patternVariableOccurrence
      prop final
   end

   class Token from StaticAnalysis.token CodeGen.token
      attr value: unit
      feat !ImAToken: unit
      meth init(Value)
	 value <- Value
	 StaticAnalysis.token, init()
      end
      meth getValue($)
	 @value
      end
      meth isConstruction($)
	 false
      end
   end

   class NameToken from Token StaticAnalysis.nameToken CodeGen.nameToken
      prop final
      attr isToplevel: unit
      feat kind: 'name'
      meth init(Value IsToplevel)
	 isToplevel <- IsToplevel
	 Token, init(Value)
      end
   end

   class ProcedureToken from Token CodeGen.procedureToken
      prop final
      feat kind: 'procedure' predicateRef
   end

   class ClauseBodyToken from Token CodeGen.clauseBodyToken
      prop final
      feat clauseBodyStatements
   end

   class BuiltinToken from Token CodeGen.builtinToken
      prop final
      feat kind: 'builtin'
   end

   class CellToken from Token
      prop final
      feat kind: 'cell'
   end

   class ChunkToken from Token
      feat kind: 'chunk'
   end

   class ArrayToken from ChunkToken
      prop final
      feat kind: 'array'
   end

   class DictionaryToken from ChunkToken
      prop final
      feat kind: 'dictionary'
   end

   class BitArrayToken from ChunkToken
      prop final
      feat kind: 'bitArray'
   end

   class ClassToken from ChunkToken
      prop final
      attr props: unit attrs: unit feats: unit meths: unit
      feat kind: 'class'
      meth setProperties(Props)
	 props <- Props
      end
      meth getProperties($)
	 @props
      end
      meth setAttributes(Attrs)
	 attrs <- Attrs
      end
      meth getAttributes($)
	 @attrs
      end
      meth setFeatures(Feats)
	 feats <- Feats
      end
      meth getFeatures($)
	 @feats
      end
      meth setMethods(Meths)
	 meths <- Meths
      end
      meth getMethods($)
	 @meths
      end
   end

   class ObjectToken from ChunkToken
      prop final
      attr classNode: unit
      feat kind: 'object'
      meth init(TheObject ClassNode)
	 value <- TheObject
	 StaticAnalysis.token, init()
	 classNode <- ClassNode
      end
      meth getClassNode($)
	 @classNode
      end
   end

   class LockToken from ChunkToken
      prop final
      feat kind: 'lock'
   end

   class PortToken from ChunkToken
      prop final
      feat kind: 'port'
   end

   class ThreadToken from Token
      prop final
      feat kind: 'thread'
   end

   class SpaceToken from Token
      prop final
      feat kind: 'space'
   end
end
