using Flux       # Main ML library
using Flux: onehot, onehotbatch, crossentropy, reset!, throttle

using Unicode    # For 'normalize'
using Random     # for 'shuffle'
using Statistics # for 'mean'

using CuArrays   # for 'gpu'

corpora = Dict()

cd(@__DIR__)
for file in readdir("corpus")
  lang = Symbol(match(r"(.*)\.txt", file).captures[1])
  corpus = split(String(read("corpus/$file")), ".")
  corpus = strip.(Unicode.normalize.(corpus, casefold=true, stripmark=true))
  corpus = filter(!isempty, corpus)
  corpora[lang] = corpus
end

langs = collect(keys(corpora))
alphabet = ['a':'z'; '0':'9'; ' '; '\n'; '_']

# See which chars will be represented as "unknown"
unique(filter(x -> x ∉ alphabet, join(vcat(values(corpora)...))))

dataset = [(onehotbatch(s, alphabet, '_'), onehot(l, langs))
           for l in langs for s in corpora[l]] |> shuffle

train, test = dataset[1:end-100], dataset[end-99:end]

train = gpu(train)
test = gpu(test)
N = 15

scanner = Chain(Dense(length(alphabet), N, σ), LSTM(N, N)) |> gpu
encoder = Dense(N, length(langs)) |> gpu

function model(x)
  state = scanner.(x.data)[end]
  reset!(scanner)
  softmax(encoder(state))
end

loss(x, y) = crossentropy(model(x), y)

testloss() = mean(loss(t...) for t in test)

opt = ADAM(params(scanner, encoder))
evalcb = () -> @show testloss()

Flux.train!(loss, train, opt, cb = throttle(evalcb, 10))
