' Copyright (c) 2013-2020 Bruce A Henderson
'
' Based on the public domain Monkey "trans" by Mark Sibly
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages
' arising from the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
'    1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
'
'    2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
'
'    3. This notice may not be removed or altered from any source
'    distribution.
'

Type TStmt Abstract
	Field errInfo$
	' whether this statement was generated by the compiler or not
	Field generated:Int
	
	Method New()
		errInfo=_errInfo
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl ) Abstract
	
	Method Semant()
		PushErr errInfo
		OnSemant
		PopErr
	End Method

	Method Copy:TStmt( scope:TScopeDecl )
		Local t:TStmt=OnCopy( scope )
		t.errInfo=errInfo
		Return t
	End Method
	
	Method OnSemant() Abstract

	Method Trans$() Abstract

	Method Clear()
	End Method
	
End Type

Type TDeclStmt Extends TStmt
	Field decl:TDecl
	
	Method Create:TDeclStmt( decl:TDecl, generated:Int = False )
		Self.decl=decl
		Self.generated = generated
		Return Self
	End Method
	
	Method CreateWithId:TDeclStmt( id$,ty:TType,init:TExpr )
		Self.decl=New TLocalDecl.Create( id,ty,init,0 )	
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Local d:TDecl = decl.Copy()
		'If Not d.scope Then
		d.scope = Null
		'End If
		Return New TDeclStmt.Create( d, generated )
	End Method
	
	Method OnSemant()
		If TLocalDecl(decl) Then
			Local tryStmtDecl:TTryStmtDecl = _env.FindTry()
			If tryStmtDecl Then
				TLocalDecl(decl).declaredInTry = tryStmtDecl
			End If
		End If
		
		decl.Semant
		' if scope is already set, don't try to add it to the current scope.
		If Not decl.scope Then
			_env.InsertDecl decl
		End If
	End Method
	
	Method Trans$()
		Return _trans.TransDeclStmt( Self )
	End Method
	
	Method Clear()
		decl.Clear()
	End Method
	
End Type

Type TAssignStmt Extends TStmt
	Field op$
	Field lhs:TExpr
	Field rhs:TExpr
	
	Method Create:TAssignStmt( op$,lhs:TExpr,rhs:TExpr, generated:Int = False )
		Self.op=op
		Self.lhs=lhs
		Self.rhs=rhs
		Self.generated = generated
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TAssignStmt.Create( op,lhs.Copy(),rhs.Copy(), generated )
	End Method
	
	Method OnSemant()
		If TIdentExpr(rhs) Then
			TIdentExpr(rhs).isRhs = True
		End If
		rhs=rhs.Semant()

		lhs=lhs.SemantSet( op,rhs )
		If TInvokeExpr( lhs ) Or TInvokeMemberExpr( lhs )
			rhs=Null
		Else
		
			' can't assign to readonly field outside of its class constructor, or anytime for readonly variable
			If TVarExpr(lhs) Or TMemberVarExpr(lhs) Then
				Local decl:TDecl
				If TVarExpr(lhs) Then
					decl = TVarExpr(lhs).decl
				Else
					Local mvExpr:TMemberVarExpr = TMemberVarExpr(lhs)
					decl = mvExpr.decl
					
					If TFieldDecl(decl) And (TInvokeExpr(mvExpr.expr) Or TInvokeMemberExpr(mvExpr.expr)) Then
						If TClassDecl(decl.scope) And TClassDecl(decl.scope).IsStruct() Then
							rhs = Null
							Warn "Discarding Field assignment of Struct returned via invocation"
							Return
						End If
					End If
					
				End If
				If decl And decl.IsReadOnly() Then
					If TFieldDecl(decl) Then
						' check scope for ctor
						Local scope:TFuncDecl = _env.FuncScope()
						If Not scope Or Not scope.IsCtor() Or (Not scope.ClassScope().ExtendsClass(decl.ClassScope())) Then
							Err "Cannot modify ReadOnly field " + decl.ident
						End If
					Else
						Err "Cannot modify ReadOnly variable " + decl.ident
					End If
				End If
				If TValDecl(decl) And TArrayType(TValDecl(decl).ty) And TArrayType(TValDecl(decl).ty).isStatic Then
					Err "Static arrays cannot be assigned in this way."
				End If
			End If
		
			If IsPointerType(lhs.exprType, 0, TType.T_POINTER | TType.T_VARPTR) And TNumericType(rhs.exprType) Then
				' with pointer assignment we don't cast the numeric to a pointer
				
			Else If IsPointerType(lhs.exprType, 0, TType.T_VAR) And TNumericType(rhs.exprType) Then
				' for var, we cast to the non-var type
				Local ty:TType = lhs.exprType.Copy()
				ty._flags :~ TType.T_VAR
				rhs=rhs.Cast( ty )
			Else
				Local splitOp:Int = True
				Select op
					Case "="
					
						rhs=rhs.Cast( lhs.exprType )
						splitOp = False
						
					Case ":*",":/",":+",":-"
					
						If TNumericType( lhs.exprType ) And lhs.exprType.EqualsType( rhs.exprType ) Then
							splitOp = False
						End If
						
						If TObjectType(lhs.exprType) Then
							Local args:TExpr[] = [rhs]
							Try
								Local decl:TFuncDecl = TFuncDecl(TObjectType(lhs.exprType).classDecl.FindFuncDecl(op, args,,,,True,SCOPE_CLASS_HEIRARCHY))
								If decl Then
									lhs = New TInvokeMemberExpr.Create( lhs, decl, args ).Semant()
									rhs = Null
									Return
								End If
							Catch error:String
								Err "Operator " + op + " cannot be used with Objects."
							End Try
						End If
					
					Case ":&",":|",":^",":shl",":shr",":mod"
					
						If (TIntType( lhs.exprType ) And lhs.exprType.EqualsType( rhs.exprType ))  Or TObjectType(lhs.exprType) Then
							splitOp = False
						End If

						If TObjectType(lhs.exprType) Then
							Local args:TExpr[] = [rhs]
							Try
								Local decl:TFuncDecl = TFuncDecl(TObjectType(lhs.exprType).classDecl.FindFuncDecl(op, args,,,,,SCOPE_CLASS_HEIRARCHY))
								If decl Then
									lhs = New TInvokeMemberExpr.Create( lhs, decl, args ).Semant()
									rhs = Null
									Return
								End If
							Catch error:String
								Err "Operator " + op + " cannot be used with Objects."
							End Try
						End If
				End Select
				
				If splitOp Then
					rhs = New TBinaryMathExpr.Create(op[1..], lhs, rhs).Semant().Cast(lhs.exprType)
					op = "="
				End If
				
			End If
		EndIf
	End Method
	
	Method Trans$()
		_errInfo=errInfo
		Return _trans.TransAssignStmt( Self )
	End Method
End Type

Type TExprStmt Extends TStmt
	Field expr:TExpr
	
	Method Create:TExprStmt( expr:TExpr )
		Self.expr=expr
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TExprStmt.Create( expr.Copy() )
	End Method
		
	Method OnSemant()
		expr=expr.Semant()
		If Not expr InternalErr "TExprStmt.OnSemant"
	End Method

	Method Trans$()
		Return _trans.TransExprStmt( Self )
	End Method
End Type

Type TReturnStmt Extends TStmt
	Field expr:TExpr
	Field fRetType:TType

	Method Create:TReturnStmt( expr:TExpr )
		Self.expr=expr
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Local r:TReturnStmt
		If expr Then
			r = New TReturnStmt.Create( expr.Copy() )
		Else
			r = New TReturnStmt.Create( Null )
		End If
		r.fRetType = fRetType
		Return r
	End Method
	
	Method OnSemant()
		Local fdecl:TFuncDecl=_env.FuncScope()
		fRetType = fdecl.retType
		If expr
			If TIdentExpr(expr) Then
				TIdentExpr(expr).isRhs = True
			End If
			If fdecl.IsCtor() Err "Constructors may not return a value."
			If TVoidType( fRetType ) Then
				Local errorText:String = "Function can not return a value."
				If Not _env.ModuleScope().IsSuperStrict() Then
					errorText :+ " You may have Strict type overriding SuperStrict type."
				End If
				Err errorText
			End If
			expr=expr.SemantAndCast( fRetType  )
			If TIdentTypeExpr(expr) Err "Function must return a value."
		Else If fdecl.IsCtor()
			' ctors do not return anything
		Else If Not TVoidType( fRetType  )
			If _env.ModuleScope().IsSuperStrict() Err "Function must return a value"
			expr=New TConstExpr.Create( fRetType ,"" ).Semant()
		EndIf
	End Method
	
	Method Trans$()
		Return _trans.TransReturnStmt( Self )
	End Method
End Type

Type TTryStmt Extends TStmt

	Field block:TBlockDecl
	Field catches:TCatchStmt[]
	Field finallyStmt:TFinallyStmt
	Field rethrowLabel:TLoopLabelDecl
	Field endTryLabel:TLoopLabelDecl
	
	Method Create:TTryStmt( block:TBlockDecl,catches:TCatchStmt[],finallyStmt:TFinallyStmt )
		Self.block=block
		Self.catches=catches
		Self.finallyStmt=finallyStmt
		Self.rethrowLabel = New TLoopLabelDecl.Create("rethrow")
		Self.endTryLabel  = New TLoopLabelDecl.Create("endtry")
		Return Self
	End Method
	
	Method OnCopy:TStmt( scope:TScopeDecl )
		Local catchCopies:TCatchStmt[] = Self.catches[..]
		For Local i:Int = 0 Until catchCopies.Length
			catchCopies[i] = TCatchStmt(catchCopies[i].Copy(scope))
		Next
		Local finallyCopy:TFinallyStmt = Null
		If finallyStmt Then finallyCopy = TFinallyStmt(finallyStmt.Copy(scope))
		Return New TTryStmt.Create(block.CopyBlock(scope), catchCopies, finallyCopy)
	End Method
	
	Method OnSemant()
		block.Semant
		Local hasObject:Int = False
		For Local i:Int = 0 Until catches.Length
			catches[i].Semant
			If hasObject Then
				PushErr catches[i].errInfo
				Err "Catch variable class extends earlier catch variable class"
			End If
			If TObjectType(catches[i].init.ty) And TObjectType(catches[i].init.ty).classdecl.ident = "Object" Then
				hasObject = True
				Continue
			End If
			For Local j:Int = 0 Until i
				If catches[i].init.ty.ExtendsType( catches[j].init.ty )
					PushErr catches[i].errInfo
					Err "Catch variable class extends earlier catch variable class"
				EndIf
			Next
		Next
		If finallyStmt Then finallyStmt.Semant
	End Method
	
	Method Trans$()
		Return _trans.TransTryStmt( Self )
	End Method
	
End Type

Type TCatchStmt Extends TStmt

	Field init:TLocalDecl
	Field block:TBlockDecl
	
	Method Create:TCatchStmt( init:TLocalDecl,block:TBlockDecl )
		Self.init=init
		Self.block=block
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TCatchStmt.Create( TLocalDecl( init.Copy() ),block.CopyBlock( scope ) )
	End Method
	
	Method OnSemant()
		init.Semant
		If (Not TObjectType( init.ty ) Or (TObjectType( init.ty ) And TObjectType( init.ty ).classDecl.IsStruct()))  And Not TStringType(init.ty) And Not TArrayType(init.ty) Err "'Catch' variables must be objects"
		block.InsertDecl init
		block.Semant
	End Method
	
	Method Trans$()
	End Method

End Type

Type TFinallyStmt Extends TStmt

	Field block:TBlockDecl
	Field finallyLabel:TLoopLabelDecl
	Field returnLabelPtrDecl:TLocalDecl
	
	Method Create:TFinallyStmt( block:TBlockDecl )
		Self.block=block
		Self.finallyLabel = New TLoopLabelDecl.Create("finally")
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TFinallyStmt.Create( block.CopyBlock( scope ) )
	End Method
	
	Method OnSemant()
		block.Semant
	End Method
	
	Method Trans$()
	End Method

End Type

Type TThrowStmt Extends TStmt
	Field expr:TExpr

	Method Create:TThrowStmt( expr:TExpr )
		Self.expr=expr
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TThrowStmt.Create( expr.Copy() )
	End Method
	
	Method OnSemant()
		expr=expr.Semant()
		If (Not TObjectType( expr.exprType ) Or (TObjectType( expr.exprType ) And TObjectType( expr.exprType ).classDecl.IsStruct()))  And Not TStringType(expr.exprType) And Not TArrayType(expr.exprType) Err "'Throw' expression must be an object"
	End Method
	
	Method Trans$()
	' TODO
		Return _trans.TransThrowStmt( Self )
	End Method
End Type

Type TLoopControlStmt Extends TStmt Abstract
	Field loop:TLoopStmt
	Field label:TExpr
End Type

Type TBreakStmt Extends TLoopControlStmt

	Method Create:TBreakStmt( label:TExpr )
		Self.label=label
		Return Self
	End Method

	Method OnSemant()
		If Not _loopnest Err "Exit statement must appear inside a loop."
		If label Then
			Local id:String
			If TIdentExpr(label) id = "'" + TIdentExpr(label).ident  + "'"
			label = label.Semant(OPTION_WANT_LOOP_LABEL)
			If Not TLoopLabelExpr(label) Err "Continue/Exit label " + id + " not found"
		End If
		If opt_debug And Not loop Then
			loop = TLoopStmt(_env.FindLoop())
			If Not loop Err "Cannot find loop for Exit."
		End If
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		If label Then
			Return New TBreakStmt.Create(label.Copy())
		Else
			Return New TBreakStmt.Create(Null)
		End If
	End Method
	
	Method Trans$()
		Return _trans.TransBreakStmt( Self )
	End Method
	
End Type

Type TContinueStmt Extends TLoopControlStmt
	
	Method Create:TContinueStmt( label:TExpr, generated:Int = False )
		Self.label=label
		Self.generated = generated
		Return Self
	End Method

	Method OnSemant()
		If Not _loopnest Err "Continue statement must appear inside a loop."
		If label Then
			Local id:String
			If TIdentExpr(label) id = "'" + TIdentExpr(label).ident  + "'"
			label = label.Semant(OPTION_WANT_LOOP_LABEL)
			If Not TLoopLabelExpr(label) Err "Continue/Exit label " + id + " not found"
		End If
		If opt_debug And Not loop Then
			loop = TLoopStmt(_env.FindLoop())
			If Not loop Err "Cannot find loop for Continue."
		End If
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		If label Then
			Return New TContinueStmt.Create(label.Copy(), generated)
		Else
			Return New TContinueStmt.Create(Null, generated)
		End If
	End Method
	
	Method Trans$()
		Return _trans.TransContinueStmt( Self )
	End Method
	
End Type

Type TIfStmt Extends TStmt
	Field expr:TExpr
	Field thenBlock:TBlockDecl
	Field elseBlock:TBlockDecl
	
	Method Create:TIfStmt( expr:TExpr,thenBlock:TBlockDecl,elseBlock:TBlockDecl, generated:Int = False )
		Self.expr=expr
		Self.thenBlock=thenBlock
		Self.elseBlock=elseBlock
		Self.generated = generated
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TIfStmt.Create( expr.Copy(),thenBlock.CopyBlock( scope ),elseBlock.CopyBlock( scope ), generated )
	End Method
	
	Method OnSemant()
		expr=expr.SemantAndCast( New TBoolType,CAST_EXPLICIT )
		thenBlock.Semant
		elseBlock.Semant
	End Method
	
	Method Trans$()
		Return _trans.TransIfStmt( Self )
	End Method
End Type

Type TLoopStmt Extends TStmt

	Field loopLabel:TLoopLabelDecl
	Field block:TBlockDecl

	Method Clear()
		block.Clear()
	End Method
End Type

Type TWhileStmt Extends TLoopStmt
	Field expr:TExpr
	
	Method Create:TWhileStmt( expr:TExpr,block:TBlockDecl,loopLabel:TLoopLabelDecl, generated:Int = False )
		Self.expr=expr
		Self.block=block
		Self.loopLabel = loopLabel
'		If loopLabel Then
			block.extra = Self
'		End If
		Self.generated = generated
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		If loopLabel Then
			Return New TWhileStmt.Create( expr.Copy(),block.CopyBlock( scope ),TLoopLabelDecl(loopLabel.Copy()), generated )
		Else
			Return New TWhileStmt.Create( expr.Copy(),block.CopyBlock( scope ),Null, generated )
		End If
	End Method
	
	Method OnSemant()
		expr=expr.SemantAndCast( New TBoolType,CAST_EXPLICIT )
		_loopnest:+1
		block.Semant
		_loopnest:-1
	End Method
	
	Method Trans$()
		Return _trans.TransWhileStmt( Self )
	End Method
End Type

Type TRepeatStmt Extends TLoopStmt
	Field expr:TExpr
	
	Method Create:TRepeatStmt( block:TBlockDecl,expr:TExpr,loopLabel:TLoopLabelDecl )
		Self.block=block
		Self.expr=expr
		Self.loopLabel=loopLabel
'		If loopLabel Then
			block.extra = Self
'		End If
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		If loopLabel Then
			Return New TRepeatStmt.Create( block.CopyBlock( scope ),expr.Copy(),TLoopLabelDecl(loopLabel.Copy()) )
		Else
			Return New TRepeatStmt.Create( block.CopyBlock( scope ),expr.Copy(),Null )
		End If
	End Method
	
	Method OnSemant()
		_loopnest:+1
		block.Semant
		_loopnest:-1
		expr=expr.SemantAndCast( New TBoolType,CAST_EXPLICIT )
	End Method
	
	Method Trans$()
		Return _trans.TransRepeatStmt( Self )
	End Method
End Type

Type TForStmt Extends TLoopStmt
	Field init:TStmt	'assignment or local decl...
	Field expr:TExpr
	Field incr:TStmt	'assignment...
	
	Method Create:TForStmt( init:TStmt,expr:TExpr,incr:TStmt,block:TBlockDecl,loopLabel:TLoopLabelDecl )
		Self.init=init
		Self.expr=expr
		Self.incr=incr
		Self.block=block
		Self.loopLabel=loopLabel
'		If loopLabel Then
			block.extra = Self
'		End If
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
	
		Local b:TBlockDecl = block.CopyBlock( scope )
	
		If loopLabel Then
			Return New TForStmt.Create( init.Copy( Null ),expr.Copy(),incr.Copy( Null ),b,TLoopLabelDecl(loopLabel.Copy()) )
		Else
			Return New TForStmt.Create( init.Copy( Null ),expr.Copy(),incr.Copy(Null),b,Null )
		End If
	End Method
	
	Method OnSemant()

		PushEnv block

		Local updateCastTypes:Int
		If TAssignStmt(init) And TIdentExpr(TAssignStmt(init).lhs) Then
			updateCastTypes = True
		Else
			' semant right-hand side first, in case the loop variable is shadowing one from rhs
			TBinaryCompareExpr(expr).rhs = TBinaryCompareExpr(expr).rhs.Semant()
		End If

		init.Semant

		If updateCastTypes Then
			' ty in the casts are currently Null - we didn't know at the time of creating the statement, what the variable type was.
			' Now we do, so we'll fill in the gaps.
			TCastExpr(TBinaryCompareExpr(expr).rhs).ty = TAssignStmt(init).lhs.exprType.Copy()
			TCastExpr(TBinaryMathExpr(TAssignStmt(incr).rhs).rhs).ty = TAssignStmt(init).lhs.exprType.Copy()
		End If

		' scope for expression part should be block-scope
		expr=expr.Semant()

		PopEnv

		' for anything other than a const value, use a new local variable
		If Not TConstExpr(TBinaryCompareExpr(expr).rhs) Then
			Local tmp:TLocalDecl=New TLocalDecl.Create( "", TBinaryCompareExpr(expr).rhs.exprType,TBinaryCompareExpr(expr).rhs,, True )
			tmp.Semant()
			Local v:TVarExpr = New TVarExpr.Create( tmp )
			TBinaryCompareExpr(expr).rhs = New TStmtExpr.Create( New TDeclStmt.Create( tmp ), v ).Semant()
		End If
		
		_loopnest:+1
		block.Semant
		_loopnest:-1

		' scope for increment part is also block-scope
		PushEnv block

		incr.Semant
		
		PopEnv

		'dodgy as hell! Reverse comparison for backward loops!
		Local assop:TAssignStmt=TAssignStmt( incr )
		Local addop:TBinaryExpr=TBinaryExpr( assop.rhs )
		Local stpval$=addop.rhs.Eval()
		If stpval.StartsWith( "-" )
			Local bexpr:TBinaryExpr=TBinaryExpr( expr )
			Select bexpr.op
			Case "<" bexpr.op=">"
			Case "<=" bexpr.op=">="
			End Select
		EndIf
		
	End Method
	
	Method Trans$()
		Return _trans.TransForStmt( Self )
	End Method
End Type

Type TAssertStmt Extends TStmt
	Field expr:TExpr
	Field elseExpr:TExpr
	
	Method Create:TAssertStmt( expr:TExpr, elseExpr:TExpr )
		Self.expr=expr
		Self.elseExpr=elseExpr
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		If elseExpr Then
			Return New TAssertStmt.Create( expr.Copy(),elseExpr.Copy() )
		Else
			Return New TAssertStmt.Create( expr.Copy(), Null )
		End If
	End Method
	
	Method OnSemant()
		expr=expr.SemantAndCast( New TBoolType,CAST_EXPLICIT )
		If elseExpr Then
			elseExpr = elseExpr.SemantAndCast(New TStringType,CAST_EXPLICIT)
		Else
			elseExpr = New TConstExpr.Create(New TStringType, "Assert failed")
		End If
	End Method
	
	Method Trans$()
		Return _trans.TransAssertStmt( Self )
	End Method
End Type

Type TEndStmt Extends TStmt
	
	Method Create:TEndStmt( )
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TEndStmt.Create( )
	End Method
	
	Method OnSemant()
	End Method
	
	Method Trans$()
		Return _trans.TransEndStmt( Self )
	End Method
End Type

Type TReleaseStmt Extends TStmt
	Field expr:TExpr

	Method Create:TReleaseStmt( expr:TExpr )
		Self.expr=expr
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TReleaseStmt.Create( expr.Copy() )
	End Method
	
	Method OnSemant()
		expr=expr.Semant()
		If Not TVarExpr( expr ) And Not TMemberVarExpr( expr) And Not TIndexExpr( expr ) err "Expression must be a variable"
		If Not TNumericType(expr.exprType) Err "Subexpression for release must be an integer variable"
	End Method
	
	Method Trans$()
		Return _trans.TransReleaseStmt( Self )
	End Method
End Type

Type TReadDataStmt Extends TStmt
	Field args:TExpr[]

	Method Create:TReadDataStmt( args:TExpr[] )
		Self.args=args
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TReadDataStmt.Create( TExpr.CopyArgs(args) )
	End Method

	Method OnSemant()
		If args Then
			For Local i:Int = 0 Until args.length
				args[i]=args[i].Semant()
				
				Local arg:TExpr = args[i]
				
				If Not TVarExpr(arg) And Not TMemberVarExpr(arg) And Not TIndexExpr(arg) And Not (TStmtExpr(arg) And TIndexExpr(TStmtExpr(arg).expr)) Then
					Err "Expression must be a variable"
				End If
			Next
		End If
	End Method

	Method Trans$()
		Return _trans.TransReadDataStmt( Self )
	End Method
	
End Type

Type TRestoreDataStmt Extends TStmt
	Field label:TExpr

	Method Create:TRestoreDataStmt( label:TExpr )
		Self.label=label
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TRestoreDataStmt.Create( label.Copy() )
	End Method

	Method OnSemant()
		If label
			Local id:String
			If TIdentExpr(label) id = "'" + TIdentExpr(label).ident  + "'"
			label = label.Semant(OPTION_WANT_DATA_LABEL)
			If Not TDataLabelExpr(label) Err "Data label " + id + " not found"
		Else
			Err "Expecting label"
		End If
	End Method

	Method Trans$()
		Return _trans.TransRestoreDataStmt( Self )
	End Method
	
End Type

Type TNativeStmt Extends TStmt
	Field raw:String
	
	Method Create:TNativeStmt( raw:String )
		Self.raw = raw
		Return Self
	End Method

	Method OnCopy:TStmt( scope:TScopeDecl )
		Return New TNativeStmt.Create( raw )
	End Method
		
	Method OnSemant()
	End Method

	Method Trans$()
		Return _trans.TransNativeStmt( Self )
	End Method
End Type
