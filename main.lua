--[[
    biscoitodasorte.koplugin — Biscoito da Sorte
    =============================================
    Exibe uma frase inspiradora ao estilo biscoito da sorte.

    Estratégia de APIs (gratuitas, sem autenticação):
      1. ZenQuotes  → https://zenquotes.io/api/random   (frases com autor)
      2. Quotable   → https://api.quotable.io/random     (frases com autor)
      3. Advice Slip → http://api.adviceslip.com/advice  (conselhos simples)
      4. Frases locais (carregadas do arquivo frases.txt na pasta do plugin)

    A ordem das APIs ativas é aleatória a cada tentativa. Se uma falhar,
    passa automaticamente para a próxima até encontrar uma resposta válida.

    Frases locais são lidas do arquivo "frases.txt" dentro da pasta do plugin.
    Esse arquivo é criado automaticamente na primeira execução (ou ao restaurar
    o padrão) com frases padrão. O formato esperado por linha:
      "frase" ou "frase|autor" ou "frase\tautor"

    Instalação:
      Copie a pasta biscoitodasorte.koplugin/ para:
        /sdcard/koreader/plugins/   (Android)
        ~/.config/koreader/plugins/ (Linux/PC)
      Reinicie o KOReader. O item aparece em Menu → Ferramentas.
--]]

-- ── dependências ──────────────────────────────────────────────────────────────
local Blitbuffer       = require("ffi/blitbuffer")
local Button           = require("ui/widget/button")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local InfoMessage      = require("ui/widget/infomessage")
local InputContainer   = require("ui/widget/container/inputcontainer")
local InputDialog      = require("ui/widget/inputdialog")
local JSON             = require("json")
local NetworkMgr       = require("ui/network/manager")
local Screen           = require("device").screen
local Size             = require("ui/size")
local TextBoxWidget    = require("ui/widget/textboxwidget")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local http             = require("socket.http")
local ltn12            = require("ltn12")
local logger           = require("logger")
local _                = require("gettext")
local util             = require("util")

-- Suporte HTTPS via LuaSec (disponível na maioria das builds modernas do KOReader)
local https_ok, ssl_https = pcall(require, "ssl.https")

-- ═════════════════════════════════════════════════════════════════════════════
-- Frases locais padrão (fallback offline)
-- ═════════════════════════════════════════════════════════════════════════════
local DEFAULT_FORTUNES = {
    { q = "Um pequeno gesto multiplica as suas alegrias." },
    { q = "A esperança iluminará os seus passos de hoje em diante." },
    { q = "A verdadeira felicidade mudará a sua visão do mundo." },
    { q = "A luz dentro de você mudará a sua visão do mundo." },
    { q = "A intuição vai lhe proporcionar momentos inesquecíveis." },
    { q = "Uma atitude positiva supera qualquer obstáculo no caminho." },
    { q = "A coragem multiplica as suas alegrias." },
    { q = "A jornada recompensa os que sabem esperar." },
    { q = "O entusiasmo supera qualquer obstáculo no caminho." },
    { q = "O conhecimento traz a calma após a tempestade." },
    { q = "Uma nova oportunidade está mais perto do que você imagina." },
    { q = "O seu coração lhe dará a resposta que procura." },
    { q = "Um sorriso sincero sempre encontra uma maneira de florescer." },
    { q = "A sorte está prestes a bater na sua porta." },
    { q = "A verdadeira felicidade multiplica as suas alegrias." },
    { q = "Uma nova oportunidade revela a sua verdadeira essência." },
    { q = "A força de vontade revela a sua verdadeira essência." },
    { q = "Uma atitude positiva traz a calma após a tempestade." },
    { q = "O verdadeiro amigo nasce das sementes que você planta hoje." },
    { q = "Um novo amanhecer nunca se esgota quando é verdadeiro." },
    { q = "A verdadeira felicidade cria laços que o tempo não apaga." },
    { q = "O poder do agora multiplica as suas alegrias." },
    { q = "A verdadeira amizade é o reflexo do seu coração puro." },
    { q = "O respeito está mais perto do que você imagina." },
    { q = "Acredite nos seus sonhos, eles estão mais perto do que você pensa." },
    { q = "O seu destino floresce no momento certo." },
    { q = "Uma atitude positiva vai transformar a sua realidade em breve." },
    { q = "O tempo é o reflexo da sua alma pura." },
    { q = "O seu coração cria laços que o tempo não apaga." },
    { q = "A luz dentro de você lhe dará a resposta que procura." },
    { q = "A vida cura até as feridas mais profundas." },
    { q = "A bondade é o seu maior tesouro escondido." },
    { q = "Um sorriso sincero está prestes a bater na sua porta." },
    { q = "A fé conspira a seu favor neste momento." },
    { q = "O entusiasmo é um presente que você deve abraçar." },
    { q = "A paciência é a fundação de um futuro brilhante." },
    { q = "A força de vontade conspira a seu favor neste momento." },
    { q = "A fé recompensa os que sabem esperar." },
    { q = "Siga o seu coração, mas leve o seu cérebro junto." },
    { q = "Uma nova oportunidade multiplica as suas alegrias." },
    { q = "O sucesso nasce das sementes que você planta hoje." },
    { q = "A jornada é o seu maior tesouro escondido." },
    { q = "A compaixão revela a sua verdadeira essência." },
    { q = "A compaixão sempre encontra uma maneira de florescer." },
    { q = "Um novo amanhecer é o primeiro passo para grandes conquistas." },
    { q = "A perseverança multiplica as suas alegrias." },
    { q = "A sorte conspira a seu favor neste momento." },
    { q = "O amanhã é um presente que você deve abraçar." },
    { q = "O conhecimento nasce das sementes que você planta hoje." },
    { q = "A esperança revela a sua verdadeira essência." },
    { q = "O sucesso guiará você por águas mais calmas." },
    { q = "Uma nova oportunidade está prestes a bater na sua porta." },
    { q = "O poder do agora nasce das sementes que você planta hoje." },
    { q = "A beleza da alma conspira a seu favor neste momento." },
    { q = "Um pequeno gesto guiará você por águas mais calmas." },
    { q = "O acaso está mais perto do que você imagina." },
    { q = "A gentileza iluminará os seus passos de hoje em diante." },
    { q = "O perdão é a fundação de um futuro brilhante." },
    { q = "A verdadeira amizade supera qualquer obstáculo no caminho." },
    { q = "A paz interior abre caminhos que você não imaginava." },
    { q = "A sorte multiplica as suas alegrias." },
    { q = "O amor verdadeiro nasce das sementes que você planta hoje." },
    { q = "Uma atitude positiva está mais perto do que você imagina." },
    { q = "A beleza da alma nunca se esgota quando é verdadeira." },
    { q = "Uma nova oportunidade vai transformar a sua realidade em breve." },
    { q = "O entusiasmo conspira a seu favor neste momento." },
    { q = "A jornada abre caminhos que você não imaginava." },
    { q = "O entusiasmo está prestes a bater na sua porta." },
    { q = "O entusiasmo guiará você por águas mais calmas." },
    { q = "O amanhã sempre encontra uma maneira de florescer." },
    { q = "Um pequeno gesto vai lhe proporcionar momentos inesquecíveis." },
    { q = "A gentileza lhe trará uma grande surpresa muito em breve." },
    { q = "A bondade cura até as feridas mais profundas." },
    { q = "A gentileza cria laços que o tempo não apaga." },
    { q = "A compaixão é o reflexo do seu coração puro." },
    { q = "A força de vontade cura até as feridas mais profundas." },
    { q = "A luz dentro de você é a chave para abrir muitas portas." },
    { q = "O respeito fortalece o seu espírito para os desafios." },
    { q = "A paz interior está mais perto do que você imagina." },
    { q = "Um novo amanhecer revela a sua verdadeira essência." },
    { q = "Um pequeno gesto é o primeiro passo para grandes conquistas." },
    { q = "A bondade é a fundação de um futuro brilhante." },
    { q = "O conhecimento traz recompensas inestimáveis." },
    { q = "Abra a sua mente para novas e maravilhosas experiências." },
    { q = "A bondade abre caminhos que você não imaginava." },
    { q = "O amanhã está mais perto do que você imagina." },
    { q = "O sucesso supera qualquer obstáculo no caminho." },
    { q = "A luz dentro de você revela os segredos mais belos da alma." },
    { q = "Um pequeno gesto é a fundação de um futuro brilhante." },
    { q = "O poder do agora é o primeiro passo para grandes conquistas." },
    { q = "Uma atitude positiva está prestes a bater na sua porta." },
    { q = "A harmonia conspira a seu favor neste momento." },
    { q = "A sabedoria está mais perto do que você imagina." },
    { q = "Uma atitude positiva vai lhe proporcionar momentos inesquecíveis." },
    { q = "O entusiasmo traz a calma após a tempestade." },
    { q = "A harmonia é o seu maior tesouro escondido." },
    { q = "Um grande amor vai lhe proporcionar momentos inesquecíveis." },
    { q = "A luz dentro de você iluminará os seus passos de hoje em diante." },
    { q = "A paz interior guiará você por águas mais calmas." },
    { q = "A força de vontade nunca se esgota quando é verdadeira." },
    { q = "O perdão supera qualquer obstáculo no caminho." },
    { q = "A harmonia iluminará os seus passos de hoje em diante." },
    { q = "A força de vontade mudará a sua visão do mundo." },
    { q = "O universo é a fundação de um futuro brilhante." },
    { q = "Um grande amor nasce das sementes que você planta hoje." },
    { q = "O amanhã lhe trará uma grande surpresa muito em breve." },
    { q = "A paciência iluminará os seus passos de hoje em diante." },
    { q = "A perseverança é a fundação de um futuro brilhante." },
    { q = "Não tenha medo de dar o primeiro passo, o universo ajudará no resto." },
    { q = "A intuição lhe dará a resposta que procura." },
    { q = "O entusiasmo é o primeiro passo para grandes conquistas." },
    { q = "O conhecimento fortalece o seu espírito para os desafios." },
    { q = "A perseverança é a luz que afasta a escuridão." },
    { q = "O seu coração cura até as feridas mais profundas." },
    { q = "Um sorriso sincero cura até as feridas mais profundas." },
    { q = "O seu coração lhe trará uma grande surpresa muito em breve." },
    { q = "Um grande amor recompensa os que sabem esperar." },
    { q = "A gentileza traz recompensas inestimáveis." },
    { q = "O respeito traz a calma após a tempestade." },
    { q = "A coragem floresce no momento certo." },
    { q = "O verdadeiro amigo mudará a sua visão do mundo." },
    { q = "O universo está mais perto do que você imagina." },
    { q = "Uma nova oportunidade é a luz que afasta a escuridão." },
    { q = "A sabedoria sempre encontra uma maneira de florescer." },
    { q = "A esperança sempre encontra uma maneira de florescer." },
    { q = "A paciência lhe dará a resposta que procura." },
    { q = "Um pequeno gesto traz recompensas inestimáveis." },
    { q = "A bondade guiará você por águas mais calmas." },
    { q = "O entusiasmo multiplica as suas alegrias." },
    { q = "Um novo amanhecer traz recompensas inestimáveis." },
    { q = "A paz interior é a chave para abrir muitas portas." },
    { q = "O sucesso é o primeiro passo para grandes conquistas." },
    { q = "O sucesso cura até as feridas mais profundas." },
    { q = "Um novo amanhecer iluminará os seus passos de hoje em diante." },
    { q = "O amanhã é a fundação de um futuro brilhante." },
    { q = "O otimismo floresce no momento certo." },
    { q = "A perseverança é a chave para abrir muitas portas." },
    { q = "O poder do agora cura até as feridas mais profundas." },
    { q = "A vida é o reflexo do seu coração puro." },
    { q = "A esperança nasce das sementes que você planta hoje." },
    { q = "O conhecimento lhe trará uma grande surpresa muito em breve." },
    { q = "O respeito multiplica as suas alegrias." },
    { q = "O entusiasmo revela os segredos mais belos da alma." },
    { q = "Confie na sua intuição, ela sabe o caminho." },
    { q = "A beleza da alma lhe dará a resposta que procura." },
    { q = "Um sorriso sincero é a luz que afasta a escuridão." },
    { q = "A bondade vai transformar a sua realidade em breve." },
    { q = "O amanhã está prestes a bater na sua porta." },
    { q = "A vida é o seu maior tesouro escondido." },
    { q = "A perseverança floresce no momento certo." },
    { q = "O verdadeiro amigo está prestes a bater na sua porta." },
    { q = "A sua criatividade cura até as feridas mais profundas." },
    { q = "O verdadeiro amigo fortalece o seu espírito para os desafios." },
    { q = "A jornada lhe dará a resposta que procura." },
    { q = "A gratidão vai transformar a sua realidade em breve." },
    { q = "O acaso recompensa os que sabem esperar." },
    { q = "O respeito é a luz que afasta a escuridão." },
    { q = "O entusiasmo mudará a sua visão do mundo." },
    { q = "Um pequeno gesto é um presente que você deve abraçar." },
    { q = "A gentileza multiplica as suas alegrias." },
    { q = "A bondade nasce das sementes que você planta hoje." },
    { q = "O conhecimento nunca se esgota quando é verdadeiro." },
    { q = "O otimismo é a fundação de um futuro brilhante." },
    { q = "A vida está prestes a bater na sua porta." },
    { q = "Um novo amanhecer nasce das sementes que você planta hoje." },
    { q = "A harmonia é o reflexo do seu coração puro." },
    { q = "O universo revela os segredos mais belos da alma." },
    { q = "A verdadeira felicidade guiará você por águas mais calmas." },
    { q = "A esperança traz recompensas inestimáveis." },
    { q = "A gentileza guiará você por águas mais calmas." },
    { q = "A gratidão vai lhe proporcionar momentos inesquecíveis." },
    { q = "A intuição nasce das sementes que você planta hoje." },
    { q = "A sabedoria cria laços que o tempo não apaga." },
    { q = "A intuição cura até as feridas mais profundas." },
    { q = "O respeito traz recompensas inestimáveis." },
    { q = "O amor verdadeiro cria laços que o tempo não apaga." },
    { q = "Uma nova oportunidade fortalece o seu espírito para os desafios." },
    { q = "O universo vai transformar a sua realidade em breve." },
    { q = "A paz interior cura até as feridas mais profundas." },
    { q = "O conhecimento é a chave para abrir muitas portas." },
    { q = "A coragem está prestes a bater na sua porta." },
    { q = "A coragem é o seu maior tesouro escondido." },
    { q = "O seu esforço cura até as feridas mais profundas." },
    { q = "O poder do agora traz recompensas inestimáveis." },
    { q = "A bondade está mais perto do que você imagina." },
    { q = "O respeito recompensa os que sabem esperar." },
    { q = "O otimismo conspira a seu favor neste momento." },
    { q = "Um sorriso sincero é a chave para abrir muitas portas." },
    { q = "A força de vontade recompensa os que sabem esperar." },
    { q = "O acaso revela os segredos mais belos da alma." },
    { q = "A verdadeira amizade floresce no momento certo." },
    { q = "A gratidão é a fundação de um futuro brilhante." },
    { q = "O amor verdadeiro vai transformar a sua realidade em breve." },
    { q = "A gentileza traz a calma após a tempestade." },
    { q = "O tempo está prestes a bater na sua porta." },
    { q = "O otimismo vai transformar a sua realidade em breve." },
    { q = "O tempo traz a calma após a tempestade." },
    { q = "A esperança é o reflexo do seu coração puro." },
    { q = "A intuição floresce no momento certo." },
    { q = "Uma atitude positiva é um presente que você deve abraçar." },
    { q = "A paz interior vai transformar a sua realidade em breve." },
    { q = "A fé é o primeiro passo para grandes conquistas." },
    { q = "A verdadeira felicidade lhe trará uma grande surpresa muito em breve." },
    { q = "O seu coração é o primeiro passo para grandes conquistas." },
    { q = "O poder do agora abre caminhos que você não imaginava." },
    { q = "Uma atitude positiva é o reflexo do seu coração puro." },
    { q = "O seu coração vai lhe proporcionar momentos inesquecíveis." },
    { q = "O entusiasmo fortalece o seu espírito para os desafios." },
    { q = "A vida abre caminhos que você não imaginava." },
    { q = "A paz interior recompensa os que sabem esperar." },
    { q = "A sabedoria conspira a seu favor neste momento." },
    { q = "Uma atitude positiva é o primeiro passo para grandes conquistas." },
    { q = "A paz interior nasce das sementes que você planta hoje." },
    { q = "A sorte sempre encontra uma maneira de florescer." },
    { q = "A fé iluminará os seus passos de hoje em diante." },
    { q = "O seu coração conspira a seu favor neste momento." },
    { q = "O verdadeiro amigo traz a calma após a tempestade." },
    { q = "A intuição guiará você por águas mais calmas." },
    { q = "A luz dentro de você é a luz que afasta a escuridão." },
    { q = "O universo é a chave para abrir muitas portas." },
    { q = "A força de vontade cria laços que o tempo não apaga." },
    { q = "Um novo amanhecer é um presente que você deve abraçar." },
    { q = "A coragem abre caminhos que você não imaginava." },
    { q = "O perdão recompensa os que sabem esperar." },
    { q = "O perdão traz a calma após a tempestade." },
    { q = "O seu esforço revela os segredos mais belos da alma." },
    { q = "A intuição recompensa os que sabem esperar." },
    { q = "O seu coração revela os segredos mais belos da alma." },
    { q = "O seu destino está prestes a bater na sua porta." },
    { q = "A verdadeira amizade traz recompensas inestimáveis." },
    { q = "A jornada está prestes a bater na sua porta." },
    { q = "O entusiasmo sempre encontra uma maneira de florescer." },
    { q = "Um sorriso sincero está mais perto do que você imagina." },
    { q = "A compaixão vai lhe proporcionar momentos inesquecíveis." },
    { q = "Um sorriso sincero vai transformar a sua realidade em breve." },
    { q = "O seu destino supera qualquer obstáculo no caminho." },
    { q = "O amanhã traz a calma após a tempestade." },
    { q = "A sabedoria abre caminhos que você não imaginava." },
    { q = "A jornada supera qualquer obstáculo no caminho." },
    { q = "A sabedoria traz a calma após a tempestade." },
    { q = "Um grande amor conspira a seu favor neste momento." },
    { q = "A fé cria laços que o tempo não apaga." },
    { q = "A jornada revela a sua verdadeira essência." },
    { q = "A intuição multiplica as suas alegrias." },
    { q = "A verdadeira amizade revela os segredos mais belos da alma." },
    { q = "O seu coração iluminará os seus passos de hoje em diante." },
    { q = "O amor verdadeiro lhe dará a resposta que procura." },
    { q = "O tempo cria laços que o tempo não apaga." },
    { q = "A coragem revela a sua verdadeira essência." },
    { q = "Um pequeno gesto supera qualquer obstáculo no caminho." },
    { q = "A sua criatividade é o reflexo do seu coração puro." },
    { q = "O seu coração fortalece o seu espírito para os desafios." },
    { q = "O amanhã mudará a sua visão do mundo." },
    { q = "A intuição revela a sua verdadeira essência." },
    { q = "A paz interior é a luz que afasta a escuridão." },
    { q = "O tempo lhe trará uma grande surpresa muito em breve." },
    { q = "O poder do agora guiará você por águas mais calmas." },
    { q = "A jornada revela os segredos mais belos da alma." },
    { q = "A sabedoria guiará você por águas mais calmas." },
    { q = "O conhecimento mudará a sua visão do mundo." },
    { q = "A vida é a fundação de um futuro brilhante." },
    { q = "O entusiasmo é a luz que afasta a escuridão." },
    { q = "A intuição iluminará os seus passos de hoje em diante." },
    { q = "A bondade é o primeiro passo para grandes conquistas." },
    { q = "O seu destino sempre encontra uma maneira de florescer." },
    { q = "O seu coração abre caminhos que você não imaginava." },
    { q = "O seu esforço lhe dará a resposta que procura." },
    { q = "A força de vontade vai lhe proporcionar momentos inesquecíveis." },
    { q = "O respeito supera qualquer obstáculo no caminho." },
    { q = "O seu coração é o reflexo da sua alma pura." },
    { q = "A bondade recompensa os que sabem esperar." },
    { q = "O sucesso revela os segredos mais belos da alma." },
    { q = "A vida iluminará os seus passos de hoje em diante." },
    { q = "O sucesso revela a sua verdadeira essência." },
    { q = "A perseverança revela a sua verdadeira essência." },
    { q = "O amanhã vai transformar a sua realidade em breve." },
    { q = "A beleza da alma revela os segredos mais belos da alma." },
    { q = "Um novo amanhecer abre caminhos que você não imaginava." },
    { q = "O poder do agora está mais perto do que você imagina." },
    { q = "O universo iluminará os seus passos de hoje em diante." },
    { q = "A paciência multiplica as suas alegrias." },
    { q = "A verdadeira amizade iluminará os seus passos de hoje em diante." },
    { q = "A beleza da alma revela a sua verdadeira essência." },
    { q = "A força de vontade multiplica as suas alegrias." },
    { q = "A sabedoria é o reflexo do seu coração puro." },
    { q = "O conhecimento cria laços que o tempo não apaga." },
    { q = "O perdão é a luz que afasta a escuridão." },
    { q = "A harmonia é a chave para abrir muitas portas." },
    { q = "A sabedoria vai lhe proporcionar momentos inesquecíveis." },
    { q = "A sabedoria é o seu maior tesouro escondido." },
    { q = "O seu esforço nunca se esgota quando é verdadeiro." },
    { q = "O verdadeiro amigo traz recompensas inestimáveis." },
    { q = "O otimismo revela a sua verdadeira essência." },
    { q = "A bondade é a chave para abrir muitas portas." },
    { q = "A sabedoria é o primeiro passo para grandes conquistas." },
    { q = "O verdadeiro amigo nunca se esgota quando é verdadeiro." },
    { q = "Uma nova oportunidade iluminará os seus passos de hoje em diante." },
    { q = "A sua criatividade traz a calma após a tempestade." },
    { q = "A paz interior é um presente que você deve abraçar." },
    { q = "A paz interior lhe trará uma grande surpresa muito em breve." },
    { q = "A intuição está prestes a bater na sua porta." },
    { q = "Um grande amor é a luz que afasta a escuridão." },
    { q = "A esperança vai lhe proporcionar momentos inesquecíveis." },
    { q = "A intuição conspira a seu favor neste momento." },
    { q = "A sorte recompensa os que sabem esperar." },
    { q = "Uma nova oportunidade guiará você por águas mais calmas." },
    { q = "O seu destino é a luz que afasta a escuridão." },
    { q = "O otimismo abre caminhos que você não imaginava." },
    { q = "A harmonia guiará você por águas mais calmas." },
    { q = "A perseverança cria laços que o tempo não apaga." },
    { q = "A força de vontade é a chave para abrir muitas portas." },
    { q = "A harmonia vai transformar a sua realidade em breve." },
    { q = "A intuição revela os segredos mais belos da alma." },
    { q = "O poder do agora é o reflexo da sua alma pura." },
    { q = "O respeito está prestes a bater na sua porta." },
    { q = "A coragem é um presente que você deve abraçar." },
    { q = "A gratidão é o seu maior tesouro escondido." },
    { q = "O amanhã revela os segredos mais belos da alma." },
    { q = "O conhecimento vai lhe proporcionar momentos inesquecíveis." },
    { q = "A paz interior é o primeiro passo para grandes conquistas." },
    { q = "A vida mudará a sua visão do mundo." },
    { q = "O amanhã nasce das sementes que você planta hoje." },
    { q = "A jornada é um presente que você deve abraçar." },
    { q = "A paz interior cria laços que o tempo não apaga." },
    { q = "A força de vontade é o primeiro passo para grandes conquistas." },
    { q = "O verdadeiro amigo é um presente que você deve abraçar." },
    { q = "O seu coração é um presente que você deve abraçar." },
    { q = "A coragem fortalece o seu espírito para os desafios." },
    { q = "A compaixão nasce das sementes que você planta hoje." },
    { q = "O conhecimento revela a sua verdadeira essência." },
    { q = "A intuição é o primeiro passo para grandes conquistas." },
    { q = "A gentileza é o primeiro passo para grandes conquistas." },
    { q = "A beleza da alma guiará você por águas mais calmas." },
    { q = "O acaso é o reflexo da sua alma pura." },
    { q = "Um novo amanhecer guiará você por águas mais calmas." },
    { q = "A gratidão lhe trará uma grande surpresa muito em breve." },
    { q = "A vida nunca se esgota quando é verdadeira." },
    { q = "A gratidão traz recompensas inestimáveis." },
    { q = "A jornada é o primeiro passo para grandes conquistas." },
    { q = "A coragem mudará a sua visão do mundo." },
    { q = "O amor verdadeiro traz a calma após a tempestade." },
    { q = "A esperança é um presente que você deve abraçar." },
    { q = "A jornada floresce no momento certo." },
    { q = "O entusiasmo é o seu maior tesouro escondido." },
    { q = "A luz dentro de você cura até as feridas mais profundas." },
    { q = "A beleza da alma está prestes a bater na sua porta." },
    { q = "A força de vontade fortalece o seu espírito para os desafios." },
    { q = "A fé é a fundação de um futuro brilhante." },
    { q = "A força de vontade sempre encontra uma maneira de florescer." },
    { q = "A perseverança traz a calma após a tempestade." },
    { q = "O verdadeiro amigo lhe trará uma grande surpresa muito em breve." },
    { q = "O acaso vai transformar a sua realidade em breve." },
    { q = "Um pequeno gesto está prestes a bater na sua porta." },
    { q = "A sabedoria revela os segredos mais belos da alma." },
    { q = "O entusiasmo é a chave para abrir muitas portas." },
    { q = "O perdão revela a sua verdadeira essência." },
    { q = "A luz dentro de você cria laços que o tempo não apaga." },
    { q = "A sorte é a luz que afasta a escuridão." },
    { q = "A vida guiará você por águas mais calmas." },
    { q = "A fé lhe trará uma grande surpresa muito em breve." },
    { q = "A coragem lhe trará uma grande surpresa muito em breve." },
    { q = "A perseverança conspira a seu favor neste momento." },
    { q = "O acaso supera qualquer obstáculo no caminho." },
    { q = "O tempo revela os segredos mais belos da alma." },
    { q = "Um sorriso sincero lhe trará uma grande surpresa muito em breve." },
}

-- Lista dinâmica de frases locais (inicializada vazia; será populada a partir do arquivo)
local local_fortunes = {}

-- ═════════════════════════════════════════════════════════════════════════════
-- APIs disponíveis (cada uma com chave, nome, descrição e função de busca)
-- ═════════════════════════════════════════════════════════════════════════════
local API_LIST = {
    {
        key  = "zenquotes",
        name = "ZenQuotes",
        desc = "Frases com autor (HTTPS)",
        fetch = function(self)
            local body = self:makeRequest("https://zenquotes.io/api/random")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and type(data) == "table" and data[1] and data[1].q ~= "" then
                    local author = (data[1].a ~= "" and data[1].a ~= "Unknown") and data[1].a or nil
                    return { q = data[1].q, a = author }
                end
            end
            return nil
        end,
    },
    {
        key  = "quotable",
        name = "Quotable",
        desc = "Frases e autores variados (HTTPS)",
        fetch = function(self)
            local body = self:makeRequest("https://api.quotable.io/random")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and data and data.content and data.content ~= "" then
                    local author = (data.author and data.author ~= "") and data.author or nil
                    return { q = data.content, a = author }
                end
            end
            return nil
        end,
    },
    {
        key  = "adviceslip",
        name = "Advice Slip",
        desc = "Conselhos simples (HTTP)",
        fetch = function(self)
            local body = self:makeRequest("http://api.adviceslip.com/advice")
            if body then
                local ok, data = pcall(JSON.decode, body)
                if ok and data and data.slip and data.slip.advice then
                    return { q = data.slip.advice, a = nil }
                end
            end
            return nil
        end,
    },
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Plugin principal
-- ═════════════════════════════════════════════════════════════════════════════
local BiscoitoDaSorte = InputContainer:extend{
    name        = "biscoitodasorte",
    fullname    = "Biscoito da Sorte",
    is_doc_only = false,
}

function BiscoitoDaSorte:init()
    self.ui.menu:registerToMainMenu(self)
    math.randomseed(os.time())

    -- Determina o diretório do plugin (pasta onde este main.lua está)
    self.plugin_dir = self:getPluginDirectory()
    self.frases_file = self.plugin_dir .. "/frases.txt"

    -- Carrega configurações: tabela com chave = true/false para cada API
    local default_enabled = {}
    for _, api in ipairs(API_LIST) do
        default_enabled[api.key] = true
    end
    self.enabled_apis = G_reader_settings:readSetting("biscoitodasorte_apis") or default_enabled

    -- Garante que o arquivo de frases exista (cria com padrão se necessário)
    self:ensureFortuneFile()
    -- Carrega as frases locais do arquivo
    self:loadFortunesFromFile()
end

--- Obtém o diretório onde este plugin está instalado.
-- Utiliza o caminho fornecido pelo KOReader (self.path), que é a forma mais confiável.
function BiscoitoDaSorte:getPluginDirectory()
    -- O KOReader define self.path com o diretório do plugin ao carregá-lo
    if self.path then
        return self.path
    end
    -- Fallback: tenta obter via debug.getinfo (útil em versões antigas ou cenários incomuns)
    local source = debug.getinfo(1, "S").source
    if source and source:match("^@") then
        local dir = source:match("^@(.*/)main%.lua$") or source:match("^@(.*/)[^/]+$")
        if dir then
            return dir
        end
    end
    -- Fallback adicional: diretório de dados do KOReader
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and DataStorage then
        return DataStorage:getDataDir() .. "/plugins/biscoitodasorte.koplugin"
    end
    -- Último recurso (improvável, mas evita nil)
    return "./plugins/biscoitodasorte.koplugin"
end

--- Cria o arquivo frases.txt com as frases padrão se ele não existir.
function BiscoitoDaSorte:ensureFortuneFile()
    if not util.fileExists(self.frases_file) then
        self:writeDefaultFortunesToFile()
    end
end

--- Escreve as frases padrão no arquivo frases.txt.
function BiscoitoDaSorte:writeDefaultFortunesToFile()
    local file, err = io.open(self.frases_file, "w")
    if not file then
        logger.warn("BiscoitoDaSorte: não foi possível criar", self.frases_file, err)
        return false
    end
    for _, entry in ipairs(DEFAULT_FORTUNES) do
        local line = entry.q
        if entry.a then
            line = line .. "|" .. entry.a
        end
        file:write(line .. "\n")
    end
    file:close()
    return true
end

--- Carrega as frases do arquivo frases.txt para a tabela local_fortunes.
-- @param show_msg se true, exibe mensagem (padrão false para inicialização silenciosa)
function BiscoitoDaSorte:loadFortunesFromFile(show_msg)
    if show_msg == nil then show_msg = false end

    local file, err = io.open(self.frases_file, "r")
    if not file then
        logger.warn("BiscoitoDaSorte: não foi possível abrir", self.frases_file, err)
        if show_msg then
            UIManager:show(InfoMessage:new{
                text = "Erro ao abrir o arquivo de frases: " .. tostring(err),
            })
        end
        return false
    end

    local new_list = {}
    local line_count = 0
    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim
        if line ~= "" then
            local quote, author
            local sep_pos = line:find("[|\t]")
            if sep_pos then
                quote = line:sub(1, sep_pos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                author = line:sub(sep_pos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                if author == "" then author = nil end
            else
                quote = line
                author = nil
            end
            if quote and quote ~= "" then
                table.insert(new_list, { q = quote, a = author })
                line_count = line_count + 1
            end
        end
    end
    file:close()

    if line_count == 0 then
        if show_msg then
            UIManager:show(InfoMessage:new{
                text = "Arquivo de frases vazio ou sem frases válidas.",
            })
        end
        return false
    end

    local_fortunes = new_list
    if show_msg then
        UIManager:show(InfoMessage:new{
            text = string.format("Carregadas %d frases do arquivo interno.", line_count),
        })
    end
    return true
end

--- Restaura as frases padrão (sobrescreve o arquivo e recarrega).
function BiscoitoDaSorte:restoreDefaultFortunes()
    if self:writeDefaultFortunesToFile() then
        self:loadFortunesFromFile(true)  -- mostra mensagem
    else
        UIManager:show(InfoMessage:new{
            text = "Erro ao restaurar o arquivo de frases padrão.",
        })
    end
end

--- Exibe uma lista com as frases carregadas.
function BiscoitoDaSorte:showLoadedFortunes()
    if #local_fortunes == 0 then
        UIManager:show(InfoMessage:new{
            text = "Nenhuma frase local carregada.",
        })
        return
    end

    local lines = {}
    local max = math.min(20, #local_fortunes)
    for i = 1, max do
        local entry = local_fortunes[i]
        local line = entry.q
        if entry.a then
            line = line .. " — " .. entry.a
        end
        table.insert(lines, tostring(i) .. ". " .. line)
    end
    if #local_fortunes > 20 then
        table.insert(lines, "... e mais " .. (#local_fortunes - 20) .. " frases.")
    end

    local msg = table.concat(lines, "\n")
    UIManager:show(InfoMessage:new{
        text = msg,
        timeout = 8,
    })
end

--- Adiciona uma nova frase ao arquivo frases.txt.
function BiscoitoDaSorte:addFortune()
    local input_dialog
    input_dialog = InputDialog:new{
        title = "Nova frase",
        input_hint = "Digite a frase (sem autor)",
        buttons = {
            {
                {
                    text = "Cancelar",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "Adicionar",
                    is_enter_default = true,
                    callback = function()
                        local phrase = input_dialog:getInputText()
                        if phrase and phrase ~= "" then
                            local file, err = io.open(self.frases_file, "a")
                            if file then
                                file:write(phrase .. "\n")
                                file:close()
                                self:loadFortunesFromFile()
                                UIManager:show(InfoMessage:new{
                                    text = "Frase adicionada com sucesso!",
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = "Erro ao salvar a frase: " .. tostring(err),
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = "A frase não pode estar vazia.",
                            })
                        end
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- ── rede ──────────────────────────────────────────────────────────────────────

function BiscoitoDaSorte:makeRequest(url)
    local chunks  = {}
    local ok_flag, code

    local function doRequest()
        local opts = {
            url     = url,
            sink    = ltn12.sink.table(chunks),
            headers = { ["User-Agent"] = "KOReader-BiscoitoDaSorte/1.0" },
        }
        if url:match("^https://") and https_ok then
            opts.verify = "none"
            ok_flag, code = ssl_https.request(opts)
        else
            ok_flag, code = http.request(opts)
        end
    end

    local pcall_ok = pcall(doRequest)

    if pcall_ok and ok_flag and tonumber(code) == 200 then
        return table.concat(chunks)
    end

    logger.warn("BiscoitoDaSorte: falha em", url, "→", tostring(code))
    return nil
end

--- Tenta buscar uma frase nas APIs habilitadas, em ordem aleatória.
function BiscoitoDaSorte:fetchFortuneFromAPI()
    local enabled = {}
    for _, api in ipairs(API_LIST) do
        if self.enabled_apis[api.key] then
            table.insert(enabled, api)
        end
    end
    if #enabled == 0 then
        return nil
    end

    for i = #enabled, 2, -1 do
        local j = math.random(i)
        enabled[i], enabled[j] = enabled[j], enabled[i]
    end

    for _, api in ipairs(enabled) do
        local result = api.fetch(self)
        if result then
            return result
        end
    end

    return nil
end

-- ── frases locais ─────────────────────────────────────────────────────────────

function BiscoitoDaSorte:getLocalFortune()
    return local_fortunes[math.random(1, #local_fortunes)]
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Widget de diálogo da frase (sem emojis)
-- ═════════════════════════════════════════════════════════════════════════════
local FortuneDialog = InputContainer:extend{
    quote   = "",
    author  = nil,
    offline = false,
    on_new  = nil,
}

function FortuneDialog:init()
    local sw  = Screen:getWidth()
    local w   = math.floor(sw * 0.84)
    local pad = Size.padding.large
    local iw  = w - pad * 2

    local quote = self.quote or ""
    if #quote > 420 then
        quote = quote:sub(1, 417) .. "…"
    end

    local body_text = quote
    if self.author then
        body_text = body_text .. "\n\n— " .. self.author
    end
    if self.offline then
        body_text = body_text .. "\n\nModo offline - frase local"
    end

    local title_w = TextWidget:new{
        text      = "Biscoito da Sorte",
        face      = Font:getFace("tfont"),
        bold      = true,
        max_width = iw,
        alignment = "center",
    }

    local divider_w = TextWidget:new{
        text      = "·  ·  ·",
        face      = Font:getFace("x_smallinfofont"),
        fgcolor   = Blitbuffer.gray(0.5),
        max_width = iw,
        alignment = "center",
    }

    local quote_w = TextBoxWidget:new{
        text      = body_text,
        face      = Font:getFace("cfont"),
        width     = iw,
        alignment = "center",
    }

    local btn_new = Button:new{
        text     = "Novo",
        width    = math.floor(iw * 0.47),
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:scheduleIn(0.15, function()
                UIManager:setDirty(nil, "full")
                if self.on_new then
                    self.on_new()
                end
            end)
        end,
    }

    local btn_close = Button:new{
        text     = "Fechar",
        width    = math.floor(iw * 0.47),
        radius   = Size.radius.button,
        callback = function()
            UIManager:close(self)
            UIManager:scheduleIn(0.1, function()
                UIManager:setDirty(nil, "full")
            end)
        end,
    }

    local btns_row = HorizontalGroup:new{
        align = "center",
        btn_new,
        HorizontalSpan:new{ width = math.floor(iw * 0.06) },
        btn_close,
    }

    local content = VerticalGroup:new{
        align = "center",
        title_w,
        VerticalSpan:new{ width = Size.span.vertical_default },
        divider_w,
        VerticalSpan:new{ width = Size.span.vertical_large },
        quote_w,
        VerticalSpan:new{ width = Size.span.vertical_large },
        btns_row,
    }

    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius     = Size.radius.window,
        padding    = pad,
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        dialog_frame,
    }
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Diálogo de configuração das APIs
-- ═════════════════════════════════════════════════════════════════════════════
local SettingsDialog = InputContainer:extend{
    plugin  = nil,
    enabled = nil,
}

function SettingsDialog:init()
    local sw   = Screen:getWidth()
    local w    = math.floor(sw * 0.84)
    local pad  = Size.padding.large
    local iw   = w - pad * 2

    local title = TextWidget:new{
        text      = "Configurar APIs",
        face      = Font:getFace("tfont"),
        bold      = true,
        max_width = iw,
        alignment = "center",
    }

    local help = TextWidget:new{
        text      = "Toque no nome para ativar/desativar",
        face      = Font:getFace("x_smallinfofont"),
        fgcolor   = Blitbuffer.gray(0.5),
        max_width = iw,
        alignment = "center",
    }

    local api_rows = VerticalGroup:new{ align = "left" }
    for _, api in ipairs(API_LIST) do
        local key = api.key
        local enabled = self.enabled[key]
        local mark = enabled and "☑ " or "☐ "
        local label = mark .. api.name .. " — " .. api.desc

        local btn = Button:new{
            text     = label,
            width    = iw,
            radius   = Size.radius.button,
            callback = function()
                self.enabled[key] = not self.enabled[key]
                UIManager:close(self)
                UIManager:show(SettingsDialog:new{
                    plugin  = self.plugin,
                    enabled = self.enabled,
                })
                UIManager:setDirty(nil, "full")
            end,
        }

        table.insert(api_rows, btn)
        table.insert(api_rows, VerticalSpan:new{ width = Size.span.vertical_small })
    end

    local btn_save = Button:new{
        text     = "Salvar",
        width    = iw,
        radius   = Size.radius.button,
        callback = function()
            self.plugin.enabled_apis = self.enabled
            G_reader_settings:saveSetting("biscoitodasorte_apis", self.enabled)
            UIManager:close(self)
            UIManager:setDirty(nil, "full")
        end,
    }

    local content = VerticalGroup:new{
        align = "center",
        title,
        VerticalSpan:new{ width = Size.span.vertical_default },
        help,
        VerticalSpan:new{ width = Size.span.vertical_large },
        api_rows,
        VerticalSpan:new{ width = Size.span.vertical_large },
        btn_save,
    }

    local dialog_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius     = Size.radius.window,
        padding    = pad,
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        dialog_frame,
    }
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Orquestração
-- ═════════════════════════════════════════════════════════════════════════════
function BiscoitoDaSorte:addToMainMenu(menu_items)
    menu_items.biscoito_da_sorte = {
        text         = "Biscoito da Sorte",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text     = "Abrir biscoito",
                callback = function()
                    self:fetchAndShowFortune()
                end,
            },
            {
                text     = "Configurar APIs",
                callback = function()
                    self:showSettings()
                end,
            },
            {
                text     = "Frases locais",
                sub_item_table = {
                    {
                        text = "Restaurar padrão",
                        callback = function()
                            self:restoreDefaultFortunes()
                        end,
                    },
                    {
                        text = "Ver frases carregadas",
                        callback = function()
                            self:showLoadedFortunes()
                        end,
                    },
                    {
                        text = "Adicionar frase",
                        callback = function()
                            self:addFortune()
                        end,
                    },
                },
            },
        },
    }
end

function BiscoitoDaSorte:showSettings()
    local enabled_copy = {}
    for k, v in pairs(self.enabled_apis) do
        enabled_copy[k] = v
    end
    UIManager:show(SettingsDialog:new{
        plugin  = self,
        enabled = enabled_copy,
    })
    UIManager:setDirty(nil, "full")
end

function BiscoitoDaSorte:fetchAndShowFortune()
    local loading = InfoMessage:new{
        text = "Abrindo seu biscoito…",
    }
    UIManager:show(loading)

    UIManager:scheduleIn(0.6, function()
        local fortune
        local offline = false

        if NetworkMgr:isConnected() then
            fortune = self:fetchFortuneFromAPI()
            if not fortune then
                offline = true
            end
        else
            offline = true
        end

        fortune = fortune or self:getLocalFortune()

        UIManager:close(loading)

        local dlg = FortuneDialog:new{
            quote   = fortune.q,
            author  = fortune.a,
            offline = offline,
            on_new  = function()
                self:fetchAndShowFortune()
            end,
        }
        UIManager:show(dlg)

        UIManager:setDirty(nil, "full")
    end)
end

return BiscoitoDaSorte
