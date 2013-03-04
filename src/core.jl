#### Types and constructors ####

# Plain arrays can be treated as images. Other types will have
# metadata associated, make yours a child of one of the following:
abstract AbstractImage{T} <: AbstractArray{T}         # image with metadata
abstract AbstractImageDirect{T} <: AbstractImage{T}   # each pixel has own value/color
abstract AbstractImageIndexed{T} <: AbstractImage{T}  # indexed images (i.e., lookup table)

# Direct image (e.g., grayscale, RGB)
type Image{T,A<:AbstractArray} <: AbstractImageDirect{T}
    data::A
    properties::Dict
end
Image{A<:AbstractArray}(data::A, props::Dict) = Image{eltype(data),A}(data,props)
Image{A<:AbstractArray}(data::A) = Image(data,Dict{String,Any}())

# Indexed image (colormap)
type ImageCmap{T,A<:AbstractArray,C<:AbstractArray} <: AbstractImageIndexed{T}
    data::A
    cmap::C
    properties::Dict
end
ImageCmap{A<:AbstractArray,C<:AbstractArray}(data::A, cmap::C, props::Dict) = ImageCmap{eltype(data),A,C}(data, cmap, props)
ImageCmap{A<:AbstractArray,C<:AbstractArray}(data::A, cmap::C) = ImageCmap(data, cmap, Dict{String,Any}())

#### Core operations ####

size(img::AbstractImage) = size(img.data)
size(img::AbstractImage, i::Integer) = size(img.data, i)

ndims(img::AbstractImage) = ndims(img.data)

copy(img::AbstractImage) = deepcopy(img)
# copy, replacing the data
copy(img::Image, data::AbstractArray) = Image(data, copy(img.properties))
copy(img::ImageCmap, data::AbstractArray) = ImageCmap(data, copy(img.cmap), copy(img.properties))

similar{T}(img::Image, ::Type{T}, dims::Dims) = Image(similar(img.data, T, dims), copy(img.properties))
similar{T}(img::Image, ::Type{T}) = Image(similar(img.data, T), copy(img.properties))
similar(img::Image) = Image(similar(img.data), copy(img.properties))
similar{T}(img::ImageCmap, ::Type{T}, dims::Dims) = ImageCmap(similar(img.data, T, dims), copy(img.cmap), copy(img.properties))
similar{T}(img::ImageCmap, ::Type{T}) = ImageCmap(similar(img.data, T), copy(img.cmap), copy(img.properties))
similar(img::ImageCmap) = ImageCmap(similar(img.data), copy(img.cmap), copy(img.properties))

convert{I<:AbstractImage}(::Type{I}, img::I) = img
# Convert an indexed image (cmap) to a direct image
function convert{ID<:AbstractImageDirect,II<:AbstractImageIndexed}(::Type{ID}, img::II)
    local data
    local prop
    if size(img.cmap, 2) == 1
        data = reshape(img.cmap[img.data[:]], size(img.data))
        prop = img.properties
    else
        newsz = tuple(size(img.data)...,size(img.cmap,2))
        data = reshape(img.cmap[img.data[:],:], newsz)
        prop = copy(img.properties)
        prop["colordim"] = length(newsz)
    end
    Image(data, prop)
end
# Convert an Image to an array. We restrict this to 2d images because of possible ambiguity in storage order conventions. In other cases---or if you don't want the storage order altered---just grab the .data field and perform whatever manipulations you need directly.
function convert{T,N}(::Type{Array{T,N}}, img)
    if N != ndims(img)
        error("Number of dimensions of the output do not agree")
    end
    if sdims(img) != 2
        error("convert() defined for two-dimensional images only")
    end
    sd = timedim(img)
    if sd != 0
        error("convert() is not defined for image sequences")
    end
    # put in canonical storage order
    p = spatialpermutation(spatialorder(Matrix), img)
    cd = colordim(img)
    if cd > 0
        push!(p, cd)
    end
    if issorted(p)
        return copy(img.data)
    else
        return permutedims(img.data, p)
    end
end

assign(img::AbstractImage, X, i::Real) = assign(img.data, X, i)
assign{T<:Real}(img::AbstractImage, X, I::Union(Real,AbstractArray{T})...) = assign(img.data, X, I...)

# ref, sub, and slice return a value or AbstractArray, not an Image
ref(img::AbstractImage, i::Real) = ref(img.data, i)
ref{T<:Real}(img::AbstractImage, I::Union(Real,AbstractArray{T})...) = ref(img.data, I...)
sub(img::AbstractImage, I::RangeIndex...) = sub(img.data, I...)
# sub{T<:Real}(img::AbstractImage, I::Union(Real,AbstractArray{T})...) = sub(img.data, I...)
slice(img::AbstractImage, I::RangeIndex...) = slice(img.data, I...)

# refim, subim, and sliceim return an Image
refim{T<:Real}(img::AbstractImage, I::Union(Real,AbstractArray{T})...) = copy(img, ref(img.data, I...))
subim(img::AbstractImage, I::RangeIndex...) = copy(img, sub(img.data, I...))
sliceim(img::AbstractImage, I::RangeIndex...) = copy(img, slice(img.data, I...))

function show(io::IO, img::AbstractImageDirect)
    IT = typeof(img)
    print(io, colorspace(img), " ", IT.name, " with:\n  data: ", summary(img.data), "\n  properties: ", img.properties)
end
function show(io::IO, img::AbstractImageIndexed)
    IT = typeof(img)
    print(io, colorspace(img), " ", IT.name, " with:\n  data: ", summary(img.data), "\n  cmap: ", summary(img.cmap), "\n  properties: ", img.properties)
end

data(img::AbstractArray) = img
data(img::AbstractImage) = img.data

min(img::AbstractImageDirect) = min(img.data)
max(img::AbstractImageDirect) = max(img.data)
# min/max deliberately not defined for AbstractImageIndexed

#### Properties ####

# Generic programming with images uses properties to obtain information. The strategy is to define a particular property name, and then write an accessor function of the same name. The accessor function provides default behavior for plain arrays and when the property is not defined. Alternatively, use get(img, "propname", default) or has(img, "propname") to define your own default behavior.

# You can define whatever properties you want. Here is a list of properties that are used in some algorithms:
#   colorspace: "RGB", "RGBA", "Gray", "Binary", "24bit", "Lab", "HSV", etc.
#   colordim: the array dimension used to store color information, or 0 if there is no dimension corresponding to color
#   timedim: the array dimension used for time (i.e., sequence), or 0 for single images
#   limits: (minvalue,maxvalue) for this type of image (e.g., (0,255) for Uint8 images, even if pixels do not reach these values)
#   pixelspacing: the spacing between adjacent pixels along spatial dimensions
#   spatialorder: a string naming each spatial dimension, in the storage order of the data array. Names can be arbitrary, but the choices "x" and "y" have special meaning (horizontal and vertical, respectively, irrespective of storage order). If supplied, you must have one entry per spatial dimension.

has(a::AbstractArray, k::String) = false
has(img::AbstractImage, k::String) = has(img.properties, k)

get(img::AbstractArray, k::String, default) = default
get(img::AbstractImage, k::String, default) = get(img.properties, k, default)

# So that defaults don't have to be evaluated unless they are needed, we also define a @get macro (thanks Toivo Hennington):
macro get(img, k, default)
    quote
        img, k = $(esc(img)), $(esc(k))
        local val
        if isa(img, StridedArray)
            val = $(esc(default))
        else
            index = Base.ht_keyindex(img.properties, k)
            val = (index > 0) ? img.properties.vals[index] : $(esc(default))
        end
        val
    end
end

# Using plain arrays, we have to make all sorts of guesses about colorspace and storage order. This can be a big problem for three-dimensional images, image sequences, cameras with more than 16-bits, etc. In such cases use an AbstractImage type.
colorspace(img::AbstractMatrix{Bool}) = "Binary"
colorspace(img::AbstractArray{Bool}) = "Binary"
colorspace(img::AbstractArray{Bool,3}) = "Binary"
colorspace{T<:Union(Int32,Uint32)}(img::AbstractMatrix{T}) = "24bit"
colorspace(img::AbstractMatrix) = "Gray"
colorspace{T}(img::AbstractArray{T,3}) = (size(img, 3) == 3) ? "RGB" : error("Cannot infer colorspace of Array, use an AbstractImage type")
colorspace(img::AbstractImage{Bool}) = "Binary"
colorspace(img::AbstractImage) = get(img.properties, "colorspace", "Unknown")

colordim{T}(img::AbstractMatrix) = 0
colordim{T}(img::AbstractArray{T,3}) = (size(img, 3) == 3) ? 3 : error("Cannot infer colordim of Array, use an AbstractImage type")
colordim(img::AbstractImageDirect) = get(img, "colordim", 0)
colordim(img::AbstractImageIndexed) = 0

timedim(img) = get(img, "timedim", 0)

limits(img::AbstractArray{Bool}) = 0,1
limits{T<:Integer}(img::AbstractArray{T}) = typemin(T), typemax(T)
limits{T<:FloatingPoint}(img::AbstractArray{T}) = zero(T), one(T)
limits(img::AbstractImage{Bool}) = 0,1
limits{T}(img::AbstractImageDirect{T}) = get(img, "limits", (typemin(T), typemax(T)))
limits(img::AbstractImageIndexed) = @get img "limits" (min(img.cmap), max(img.cmap))

pixelspacing{T}(img::AbstractArray{T,3}) = (size(img, 3) == 3) ? [1.0,1.0] : error("Cannot infer pixelspacing of Array, use an AbstractImage type")
pixelspacing(img::AbstractMatrix) = [1.0,1.0]
pixelspacing(img::AbstractImage) = @get img "pixelspacing" _pixelspacing(img)
_pixelspacing(img::AbstractImage) = ones(sdims(img))

# defaults for plain arrays ("vertical-major")
const yx = ["y", "x"]
# order used in Cairo & most image file formats (with color as the very first dimension)
const xy = ["x", "y"]
spatialorder(::Type{Matrix}) = yx
spatialorder(img::AbstractArray) = (sdims(img) == 2) ? yx : error("Wrong number of spatial dimensions for plain Array, use an AbstractImage type")
spatialorder(img::AbstractImage) = get(img, "spatialorder", nothing)

# number of spatial dimensions in the image
sdims(img) = ndims(img) - (colordim(img) != 0) - (timedim(img) != 0)

# number of time slices
function nimages(img)
    sd = timedim(img)
    if sd > 0
        return size(img, sd)
    else
        return 1
    end
end

# indices of spatial coordinates
function coords_spatial(img)
    ind = [1:ndims(img)]
    cd = colordim(img)
    sd = timedim(img)
    if cd > sd
        delete!(ind, cd)
        if sd > 0
            delete!(ind, sd)
        end
    elseif sd > cd
        delete!(ind, sd)
        if sd > 0
            delete!(ind, cd)
        end
    end
    ind
end

# size of the spatial grid
function size_spatial(img)
    sz = size(img)
    sz[coords_spatial(img)]
end

# width and height, translating "x" and "y" spatialorder into horizontal and vertical, respectively
widthheight(img::AbstractArray, p) = size(img, p[1]), size(img, p[2])
widthheight(img::AbstractArray) = widthheight(img, spatialpermutation(xy, img))

# Calculate the permutation needed to put the spatial dimensions into a specified order
spatialpermutation(to, img::AbstractArray) = default_permutation(to, spatialorder(img))
function spatialpermutation(to, img::AbstractImage)
    so = spatialorder(img)
    if so != nothing
        return default_permutation(to, so)
    else
        if sdims(img) != 2
            error("Cannot guess default spatialorder when there are more than 2 spatial dimensions")
        end
        return default_permutation(to, yx)
    end
end

# Permute the dimensions of an image, also permuting the relevant properties. If you have non-default properties that are vectors or matrices relative to spatial dimensions, include their names in the list of spatialprops.
function permutedims(img::AbstractImage, p, spatialprops::Vector)
    if length(p) != ndims(img)
        error("The permutation must have length equal to the number of dimensions")
    end
    ip = invperm(p)
    cd = colordim(img)
    sd = timedim(img)
    ret = copy(img, permutedims(img.data, p))
    if cd > 0
        ret.properties["colordim"] = ip[cd]
        p = setdiff(p, cd)
    end
    if sd > 0
        ret.properties["timedim"] = ip[sd]
        p = setdiff(p, sd)
    end
    if !isempty(spatialprops)
        ip = sortperm(p)
        for prop in spatialprops
            a = img.properties[prop]
            if isa(a, AbstractVector)
                ret.properties[prop] = a[ip]
            elseif isa(a, AbstractMatrix) && size(a,1) == size(a,2)
                ret.properties[prop] = a[ip,ip]
            else
                error("Do not know how to handle property ", prop)
            end
        end
    end
    ret
end
permutedims(img::AbstractImage, p) = permutedims(img, p, spatialproperties(img))

# Default list of spatial properties possessed by an image
function spatialproperties(img::AbstractImage)
    spatialprops = ASCIIString[]
    if has(img, "spatialorder")
        push!(spatialprops, "spatialorder")
    end
    if has(img, "pixelspacing")
        push!(spatialprops, "pixelspacing")
    end
    spatialprops
end


#### Low-level utilities ####
function permutation(to, from)
    n = length(to)
    d = Dict(tuple(from...), tuple([1:length(from)]...))
    ind = Array(Int, n)
    for i = 1:n
        ind[i] = get(d, to[i], 0)
    end
    ind
end

function default_permutation(to, from)
    p = permutation(to, from)
    pzero = p .== 0
    if any(pzero)
        p[pzero] = setdiff(1:length(to), p)
    end
    p
end
