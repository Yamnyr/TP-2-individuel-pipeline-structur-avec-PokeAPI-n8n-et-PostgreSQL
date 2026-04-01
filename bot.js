require('dotenv').config();
const { Client, GatewayIntentBits } = require('discord.js');
const axios = require('axios');

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent
    ]
});

client.on('ready', () => {
    console.log(`✅ Bot connecté en tant que ${client.user.tag}`);
});

client.on('messageCreate', async (message) => {
    if (message.author.bot) return;

    try {
        await axios.post(process.env.WEBHOOK_URL, {
            content: message.content.toLowerCase().trim(),
            channel_id: message.channel.id
        });

    } catch (error) {
        console.error(error.message);
    }
});

client.login(process.env.DISCORD_TOKEN);