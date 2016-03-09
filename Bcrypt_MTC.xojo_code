#tag Module
Protected Module Bcrypt_MTC
	#tag Method, Flags = &h1
		Protected Function Bcrypt(key As String, salt As String) As String
		  if salt = "" or key = "" then 
		    return ""
		  end if
		  
		  #pragma BackgroundTasks False
		  #pragma BoundsChecking False
		  #pragma NilObjectChecking False
		  #pragma StackOverflowChecking False
		  
		  dim r as string
		  
		  dim state as Blowfish_MTC
		  dim rounds as Integer
		  dim logr, minor as UInt8
		  dim ciphertext as MemoryBlock = "OrpheanBeholderScryDoubt"
		  dim precomputedCiphertext as string = "hprOBnaeloheSredDyrctbuo" // Same every time
		  dim csalt as new MemoryBlock( BCRYPT_MAXSALT )
		  dim cdata as new MemoryBlock( BCRYPT_BLOCKS * 4 )
		  dim n as Integer
		  
		  dim saltFields() as string = salt.Split( "$" )
		  
		  if saltFields.Ubound <> 3 then
		    return ""
		  end if
		  
		  dim saltVersionString as string = saltFields( 1 )
		  dim saltVersion as integer = Val( saltVersionString )
		  dim saltRounds as string = saltFields( 2 )
		  dim saltText as string = saltFields( 3 )
		  
		  if saltVersionString = "" or saltVersion > Val( BCRYPT_VERSION ) then
		    return ""
		  end if
		  
		  saltVersionString = NthFieldB( saltVersionString, str( saltVersion ), 2 )
		  if saltVersionString <> "" then
		    select case saltVersionString
		    case "a", "x", "y"
		      minor = AscB( "a" )
		    else
		      return ""
		    end select
		  end if
		  
		  n = Val( saltRounds )
		  if n < 0 or n > 31 then
		    return ""
		  end if
		  
		  logr = n
		  rounds = Bitwise.ShiftLeft( 1, logr )
		  if rounds < BCRYPT_MINROUNDS then
		    return ""
		  end if
		  
		  if ( ( saltText.LenB * 3 ) / 4 ) < BCRYPT_MAXSALT then
		    return ""
		  end if
		  
		  // Get the raw data behind the salt
		  pDecodeBase64( csalt, saltText )
		  if minor >= AscB( "a" ) then
		    key = key + ChrB( 0 ) // Set it up as CString
		  end if
		  
		  // Set up S-Boxes and Subkeys
		  state = new Blowfish_MTC
		  state.ExpandState( csalt, key )
		  dim lastRound as UInt32 = rounds - 1
		  '#pragma warning "REMOVE THIS!!"
		  'lastRound = 99
		  for k as Integer = 0 to lastRound
		    state.Expand0State( key )
		    state.Expand0State( csalt )
		  next k
		  
		  dim lastBlock as UInt32 = BCRYPT_BLOCKS - 1
		  cdata = precomputedCiphertext // Same every time, no need to recompute
		  
		  // Now to encrypt
		  for k as Integer = 0 to 63
		    state.Encrypt( cdata )
		  next k
		  
		  cipherText.LittleEndian = false // Make sure the bytes are copied in the right order
		  cdata.LittleEndian = not ciphertext.LittleEndian // Will copy the bytes in reverse order
		  for i as Integer = 0 to lastBlock
		    dim dataIndex as Integer = i * 4
		    ciphertext.UInt32Value( dataIndex ) = cdata.UInt32Value( dataIndex )
		  next i
		  
		  r = "$" + BCRYPT_VERSION + ChrB( minor ) + "$" + format( logr, "00" ) + "$"
		  
		  dim buffer as new MemoryBlock( 128 )
		  pEncodeBase64( buffer, csalt )
		  r = r + buffer.CString( 0 )
		  
		  ciphertext.Size = ciphertext.Size - 1 // Lop off last character
		  pEncodeBase64( buffer, ciphertext )
		  r = r + buffer.CString( 0 )
		  
		  return r
		End Function
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Function GenerateSalt(rounds As UInt8, preferredPrefix As Prefix = Prefix.A) As String
		  dim csalt as MemoryBlock = Crypto.GenerateRandomBytes( BCRYPT_MAXSALT )
		  
		  if rounds < 4 then
		    rounds = 4
		  elseif rounds > 31 then
		    rounds = 31
		  end if
		  
		  return pEncodeSalt( csalt, rounds, preferredPrefix )
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function pChar64(c As Byte) As Integer
		  static index64() as Integer = Array( _
		  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, _
		  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, _
		  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, _
		  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, _
		  255, 255, 255, 255, 255, 255, 0, 1, 54, 55, _
		  56, 57, 58, 59, 60, 61, 62, 63, 255, 255, _
		  255, 255, 255, 255, 255, 2, 3, 4, 5, 6, _
		  7, 8, 9, 10, 11, 12, 13, 14, 15, 16, _
		  17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, _
		  255, 255, 255, 255, 255, 255, 28, 29, 30, _
		  31, 32, 33, 34, 35, 36, 37, 38, 39, 40, _
		  41, 42, 43, 44, 45, 46, 47, 48, 49, 50, _
		  51, 52, 53, 255, 255, 255, 255, 255 _
		  )
		  
		  if c > 127 then
		    return 255
		  else
		    return index64( c )
		  end if
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub pDecodeBase64(buffer As MemoryBlock, data As MemoryBlock)
		  #pragma BackgroundTasks False
		  #pragma BoundsChecking False
		  #pragma NilObjectChecking False
		  #pragma StackOverflowChecking False
		  
		  dim bp, p as integer
		  dim c1, c2, c3, c4 as byte
		  dim lastByteIndex as integer = buffer.Size - 1
		  dim bufferPtr as Ptr = buffer
		  dim dataPtr as Ptr = data
		  
		  while bp <= lastByteIndex
		    c1 = pChar64( dataPtr.Byte( p ) )
		    c2 = pChar64( dataPtr.Byte( p + 1 ) )
		    
		    if c1 = 255 or c2 = 255 then
		      exit while
		    end if
		    
		    bufferPtr.Byte( bp ) = Bitwise.ShiftLeft( c1, 2, 8 ) or Bitwise.ShiftRight( c2 and &h30, 4, 8 )
		    bp = bp + 1
		    if bp > lastByteIndex then
		      exit while
		    end if
		    
		    c3 = pChar64( dataPtr.Byte( p + 2 ) )
		    if c3 = 255 then
		      exit while
		    end if
		    
		    bufferPtr.Byte( bp ) = Bitwise.ShiftLeft( c2 and &h0F, 4, 8 ) or Bitwise.ShiftRight( c3 and &h3C, 2, 8 )
		    bp = bp + 1
		    if bp > lastByteIndex then
		      exit while
		    end if
		    
		    c4 = pChar64( dataPtr.Byte( p + 3 ) )
		    if c4 = 255 then
		      exit while
		    end if
		    bufferPtr.Byte( bp ) = Bitwise.ShiftLeft( c3 and &h03, 6, 8 ) or c4
		    bp = bp + 1
		    
		    p = p + 4
		  wend
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub pEncodeBase64(buffer As MemoryBlock, data As MemoryBlock)
		  #pragma BackgroundTasks False
		  #pragma BoundsChecking False
		  #pragma NilObjectChecking False
		  #pragma StackOverflowChecking False
		  
		  dim lastByteIndex as integer = data.Size - 1
		  dim bp, p as integer
		  dim bufferPtr as Ptr = buffer
		  dim dataPtr as Ptr = data
		  dim base64AlphabetPtr as Ptr = zBase64AlphabetMB
		  
		  dim c1, c2 as byte
		  
		  while ( p <= lastByteIndex )
		    c1 = dataPtr.Byte( p )
		    p = p + 1
		    
		    bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( Bitwise.ShiftRight( c1, 2, 8 ) )
		    bp = bp + 1
		    
		    c1 = Bitwise.ShiftLeft( c1 and &h03, 4, 8 )
		    if p > lastByteIndex then
		      bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( c1 )
		      bp = bp + 1
		      exit while
		    end if
		    
		    c2 = dataPtr.Byte( p )
		    p = p + 1
		    
		    c1 = c1 or ( Bitwise.ShiftRight( c2, 4, 8 ) and &h0F )
		    bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( c1 )
		    bp = bp + 1
		    
		    c1 = Bitwise.ShiftLeft( c2 and &h0F, 2, 8 )
		    if p > lastByteIndex then
		      bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( c1 )
		      bp = bp + 1
		      exit while
		    end if
		    
		    c2 = dataPtr.Byte( p )
		    p = p + 1
		    
		    c1 = c1 or ( Bitwise.ShiftRight( c2, 6 , 8) and &h03 )
		    bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( c1 )
		    bp = bp + 1
		    bufferPtr.Byte( bp ) = base64AlphabetPtr.Byte( c2 and &h3F )
		    bp = bp + 1
		  wend
		  
		  bufferPtr.Byte( bp ) = 0
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function pEncodeSalt(csalt As MemoryBlock, rounds As UInt8, preferredPrefix As Prefix = Prefix.A) As String
		  dim prefixLetter as string = Chr( Integer( preferredPrefix ) )
		  
		  dim salt as string = "$" + BCRYPT_VERSION + prefixLetter + "$"
		  salt = salt + format( rounds, "00" ) + "$"
		  
		  dim buffer as new MemoryBlock( csalt.Size * 2 )
		  pEncodeBase64( buffer, csalt )
		  
		  salt = salt + buffer.CString( 0 )
		  return salt
		  
		End Function
	#tag EndMethod


	#tag Note, Name = BCrypt Notes
		C code for bcrypt here:
		
		http://ftp3.usa.openbsd.org/pub/OpenBSD/src/lib/libc/crypt/bcrypt.c
	#tag EndNote

	#tag Note, Name = License
		
		This is an open-source project.
		
		This project is distributed AS-IS and no warranty of fitness for any particular purpose 
		is expressed or implied. You may freely use or modify this project or any part of 
		within as long as this notice or any other legal notice is left undisturbed.
		
		You may distribute a modified version of this project as long as all modifications 
		are clearly documented and accredited.
		
		This project was created by Kem Tekinay (ktekinay@mactechnologies.com) and
		is housed at:
		
		https://github.com/ktekinay/Blowfish
	#tag EndNote


	#tag ComputedProperty, Flags = &h21
		#tag Getter
			Get
			  static mb as MemoryBlock = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
			  return mb
			End Get
		#tag EndGetter
		Private zBase64AlphabetMB As MemoryBlock
	#tag EndComputedProperty


	#tag Constant, Name = BCRYPT_BLOCKS, Type = Double, Dynamic = False, Default = \"6", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = BCRYPT_MAXSALT, Type = Double, Dynamic = False, Default = \"16", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = BCRYPT_MINROUNDS, Type = Double, Dynamic = False, Default = \"6", Scope = Protected
	#tag EndConstant

	#tag Constant, Name = BCRYPT_VERSION, Type = String, Dynamic = False, Default = \"2", Scope = Protected
	#tag EndConstant


	#tag Enum, Name = Prefix, Type = Integer, Flags = &h1
		A = 97
		  X = 120
		Y = 121
	#tag EndEnum


	#tag ViewBehavior
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			Type="String"
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
		#tag EndViewProperty
	#tag EndViewBehavior
End Module
#tag EndModule
